import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '/flutter_flow/flutter_flow_util.dart';
export '../../state/app_state_notifier.dart';
import '/index.dart';
import '/main.dart';
export '/main.dart';
import '../../pages/artisan_complete_profile/artisan_complete_profile_widget.dart';
import '../../pages/static_splash/static_splash_widget.dart';
import '../../pages/artisan_kyc_page/artisan_kyc_guard.dart';
import '../../utils/auth_guard.dart';
import '../../pages/booking_details/booking_details_widget.dart';
import '../../state/auth_notifier.dart';
import '../../state/app_state_notifier.dart';

export 'serialization_util.dart';
export 'ff_navigation_adapters.dart';

const kTransitionInfoKey = '__transition_info__';

// Backwards-compatible global app navigator key. We do not pass this into
// GoRouter (prefer context-based navigation), but some legacy code still
// references `appNavigatorKey`; keep it defined to avoid widespread changes.
GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AuthNotifier auth) {
  return GoRouter(
      observers: [routeObserver],
      // App should start on the static splash page and only proceed to
      // /splash2 after the static splash's internal delay. Do not auto-redirect
      // elsewhere on app launch.
      initialLocation: StaticSplashWidget.routePath,
      debugLogDiagnostics: true,
      refreshListenable: auth,
      // Do not use a global navigatorKey - prefer GoRouter's context-based navigation
      errorBuilder: (context, state) => AppStateNotifier.instance.showSplashImage
          ? StaticSplashWidget()
          : Splash2Widget(),
      // Global redirect: enforce unauthenticated/guest/authenticated rules
      redirect: (context, state) {
        try {
          final loc = state.uri.path;

          // If unauthenticated, only allow the auth/onboarding flow pages.
          if (auth.status == AuthStatus.unauthenticated) {
            final allowed = {
              StaticSplashWidget.routePath,
              Splash2Widget.routePath,
              SplashScreenPage2Widget.routePath,
              LoginAccountWidget.routePath,
              CreateAccount2Widget.routePath,
              // Allow direct access to the forget password page without redirect
              ForgetPasswordWidget.routePath,
            };
            if (allowed.contains(loc)) return null;
            // Redirect any other path to splash2 so user must choose login/register/guest
            return Splash2Widget.routePath;
          }

          // If authenticated, prevent navigating back to login/register routes
          if (auth.isAuthenticated && (loc == LoginAccountWidget.routePath || loc == CreateAccount2Widget.routePath || loc == WelcomeAfterSignupWidget.routePath)) {
            // Redirect to role-specific landing
            if (auth.status == AuthStatus.authenticatedArtisan) return ArtisanDashboardPageWidget.routePath;
            return HomePageWidget.routePath;
          }

          // Guests: no global redirects; allow browsing
        } catch (_) {}
        return null;
      },
      // Build the FFRoute list here so we can log the registered routes in debug mode
      routes: () {
        final ffRoutes = <FFRoute>[
          // Static splash: first screen on app launch. It will navigate to /splash2
          // after its internal delay. The router should not auto-redirect from here.
          FFRoute(
            name: StaticSplashWidget.routeName,
            path: StaticSplashWidget.routePath,
            builder: (context, params) => StaticSplashWidget(),
          ),
          FFRoute(
            name: '_initialize',
            path: '/',
            builder: (context, _) => AppStateNotifier.instance.showSplashImage ? StaticSplashWidget() : Splash2Widget(),
          ),
          FFRoute(
            name: CreateAccount2Widget.routeName,
            path: CreateAccount2Widget.routePath,
            requireNoAuth: true,
            builder: (context, params) => CreateAccount2Widget(
              initialRole: params.getParam<String>('role', ParamType.String),
            ),
          ),
          FFRoute(
            name: Splash2Widget.routeName,
            path: Splash2Widget.routePath,
            builder: (context, params) => Splash2Widget(),
          ),
          FFRoute(
            name: LoginAccountWidget.routeName,
            path: LoginAccountWidget.routePath,
            requireNoAuth: true,
            builder: (context, params) => LoginAccountWidget(),
          ),
          FFRoute(
              name: ProfileWidget.routeName,
              path: ProfileWidget.routePath,
              requireAuth: true,
              builder: (context, params) {
                final isArtisan = AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false;
                final profilePage = isArtisan ? ArtisanProfilepageWidget() : ProfileWidget();
                final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
                return params.isEmpty
                    ? NavBarPage(initialPage: 'profile', showDiscover: showDiscoverNow)
                    : NavBarPage(
                        initialPage: 'profile',
                        page: profilePage,
                        showDiscover: showDiscoverNow,
                      );
              }),
          FFRoute(
            name: SearchPageWidget.routeName,
            path: SearchPageWidget.routePath,
            builder: (context, params) => SearchPageWidget(),
          ),
          FFRoute(
              name: BookingPageWidget.routeName,
              path: BookingPageWidget.routePath,
              builder: (context, params) {
                final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
                return params.isEmpty
                  ? NavBarPage(initialPage: 'BookingPage', showDiscover: showDiscoverNow)
                  : NavBarPage(
                      initialPage: 'BookingPage',
                      page: BookingPageWidget(),
                      showDiscover: showDiscoverNow,
                    );
              }),
          FFRoute(
            name: NotificationPageWidget.routeName,
            path: NotificationPageWidget.routePath,
            builder: (context, params) => NotificationPageWidget(),
          ),
          FFRoute(
              name: HomePageWidget.routeName,
              path: HomePageWidget.routePath,
              builder: (context, params) {
                final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
                return params.isEmpty
                  ? NavBarPage(initialPage: 'homePage', showDiscover: showDiscoverNow)
                  : HomePageWidget();
              },
          ),
          FFRoute(
              name: DiscoverPageWidget.routeName,
              path: DiscoverPageWidget.routePath,
              builder: (context, params) {
                final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
                return params.isEmpty
                  ? NavBarPage(initialPage: 'DiscoverPage', showDiscover: showDiscoverNow)
                  : NavBarPage(
                      initialPage: 'DiscoverPage',
                      page: DiscoverPageWidget(),
                      showDiscover: showDiscoverNow,
                    );
              }),
          FFRoute(
            name: AllServicepageWidget.routeName,
            path: AllServicepageWidget.routePath,
            builder: (context, params) => AllServicepageWidget(),
          ),
          FFRoute(
            name: MessageClientWidget.routeName,
            path: MessageClientWidget.routePath,
            builder: (context, params) {
              // Read bookingId/threadId via FFParameters helper (supports query/path/extras)
              final bid = params.getParam<String>('bookingId', ParamType.String);
              final tid = params.getParam<String>('threadId', ParamType.String);
              return MessageClientWidget(
                bookingId: bid,
                threadId: tid,
              );
            },
          ),
          FFRoute(
            name: EditProfileUserWidget.routeName,
            path: EditProfileUserWidget.routePath,
            builder: (context, params) => EditProfileUserWidget(),
          ),
          FFRoute(
            name: ArtisanCompleteProfileWidget.routeName,
            path: ArtisanCompleteProfileWidget.routePath,
            builder: (context, params) => ArtisanCompleteProfileWidget(),
          ),
          FFRoute(
            name: UserWalletpageWidget.routeName,
            path: UserWalletpageWidget.routePath,
            builder: (context, params) => UserWalletpageWidget(),
          ),
          FFRoute(
            name: CreatePostpageWidget.routeName,
            path: CreatePostpageWidget.routePath,
            builder: (context, params) => CreatePostpageWidget(),
          ),
          FFRoute(
            name: JobPublishpageWidget.routeName,
            path: JobPublishpageWidget.routePath,
            builder: (context, params) => JobPublishpageWidget(),
          ),
          FFRoute(
            name: UpdateProfilepageWidget.routeName,
            path: UpdateProfilepageWidget.routePath,
            builder: (context, params) => UpdateProfilepageWidget(),
          ),
          FFRoute(
            name: ArtisanProfileupdateWidget.routeName,
            path: ArtisanProfileupdateWidget.routePath,
            builder: (context, params) => ArtisanProfileupdateWidget(),
          ),
          FFRoute(
            name: ContactUsPageWidget.routeName,
            path: ContactUsPageWidget.routePath,
            builder: (context, params) => ContactUsPageWidget(),
          ),
          FFRoute(
            name: ForgetPasswordWidget.routeName,
            path: ForgetPasswordWidget.routePath,
            builder: (context, params) => ForgetPasswordWidget(),
          ),
          FFRoute(
            name: UpdatePasswordWidget.routeName,
            path: UpdatePasswordWidget.routePath,
            builder: (context, params) => UpdatePasswordWidget(),
          ),
          FFRoute(
            name: VerificationPageWidget.routeName,
            path: VerificationPageWidget.routePath,
            builder: (context, params) => VerificationPageWidget(),
          ),
          FFRoute(
            name: RequestQuotePageWidget.routeName,
            path: RequestQuotePageWidget.routePath,
            builder: (context, params) => RequestQuotePageWidget(),
          ),
          FFRoute(
            name: PaymentScreenPage3Widget.routeName,
            path: PaymentScreenPage3Widget.routePath,
            builder: (context, params) => PaymentScreenPage3Widget(),
          ),
          FFRoute(
            name: ReviewRatingsPageWidget.routeName,
            path: ReviewRatingsPageWidget.routePath,
            builder: (context, params) => ReviewRatingsPageWidget(),
          ),
          FFRoute(
            name: RequestArtisanPage1Widget.routeName,
            path: RequestArtisanPage1Widget.routePath,
            requireAuth: true,
            builder: (context, params) => RequestArtisanPage1Widget(),
          ),
          FFRoute(
            name: QuoteSummaryPage2Widget.routeName,
            path: QuoteSummaryPage2Widget.routePath,
            builder: (context, params) => QuoteSummaryPage2Widget(),
          ),
          FFRoute(
            name: CompeletePaymentPage4Widget.routeName,
            path: CompeletePaymentPage4Widget.routePath,
            builder: (context, params) => CompeletePaymentPage4Widget(),
          ),
          FFRoute(
            name: DepositSuccessPageWidget.routeName,
            path: DepositSuccessPageWidget.routePath,
            builder: (context, params) => DepositSuccessPageWidget(),
            requireAuth: true,
          ),
          FFRoute(
            name: ArtisanProfilepageWidget.routeName,
            path: ArtisanProfilepageWidget.routePath,
            builder: (context, params) {
              final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
              return params.isEmpty
                  ? NavBarPage(initialPage: 'profile', showDiscover: showDiscoverNow)
                  : ArtisanProfilepageWidget();
            },
          ),
          FFRoute(
            name: ArtisanJobsHistoryWidget.routeName,
            path: ArtisanJobsHistoryWidget.routePath,
            builder: (context, params) => ArtisanJobsHistoryWidget(),
          ),
          FFRoute(
            name: SeeAllImagesPageWidget.routeName,
            path: SeeAllImagesPageWidget.routePath,
            builder: (context, params) => SeeAllImagesPageWidget(),
          ),
          FFRoute(
              name: JobPostPageWidget.routeName,
              path: JobPostPageWidget.routePath,
              builder: (context, params) {
                final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
                return params.isEmpty
                  ? NavBarPage(initialPage: 'JobPostPage', showDiscover: showDiscoverNow)
                  : NavBarPage(
                      initialPage: 'JobPostPage',
                      page: JobPostPageWidget(),
                      showDiscover: showDiscoverNow,
                    );
              }),
          FFRoute(
            name: ArtisanKycWidget.routeName,
            path: ArtisanKycWidget.routePath,
            requireAuth: true,
            builder: (context, params) => ArtisanKycGuard(),
          ),
          FFRoute(
            name: CreateJobPage1Widget.routeName,
            path: CreateJobPage1Widget.routePath,
            builder: (context, params) => CreateJobPage1Widget(),
          ),
          FFRoute(
            name: JobHistoryPageWidget.routeName,
            path: JobHistoryPageWidget.routePath,
            builder: (context, params) => JobHistoryPageWidget(),
          ),
          FFRoute(
            name: JobDetailPageWidget.routeName,
            path: JobDetailPageWidget.routePath,
            builder: (context, params) => JobDetailPageWidget(),
          ),
          FFRoute(
            name: ArtisanDashboardPageWidget.routeName,
            path: ArtisanDashboardPageWidget.routePath,
            builder: (context, params) {
              final showDiscoverNow = !(AppStateNotifier.instance.profile?['role']?.toString().toLowerCase().contains('artisan') ?? false);
              return NavBarPage(initialPage: 'homePage', showDiscover: showDiscoverNow);
            },
          ),
          FFRoute(
            name: SplashScreenPage2Widget.routeName,
            path: SplashScreenPage2Widget.routePath,
            builder: (context, params) => SplashScreenPage2Widget(),
          ),
          FFRoute(
            name: WelcomeAfterSignupWidget.routeName,
            path: WelcomeAfterSignupWidget.routePath,
            requireNoAuth: true,
            builder: (context, params) => WelcomeAfterSignupWidget(
              role: params.getParam<String>('role', ParamType.String),
            ),
          ),
          FFRoute(
            name: 'BookingDetails',
            path: BookingDetailsWidget.routePath,
            builder: (context, params) => BookingDetailsWidget(
              bookingId: params.getParam<String>('bookingId', ParamType.String),
              threadId: params.getParam<String>('threadId', ParamType.String),
              jobTitle: params.getParam<String>('jobTitle', ParamType.String),
              bookingPrice: params.getParam<String>('bookingPrice', ParamType.String),
              bookingDateTime: params.getParam<String>('bookingDateTime', ParamType.String),
              success: params.getParam<bool>('success', ParamType.bool),
            ),
          ),
          // Backwards-compatible alias route so external links or legacy callers
          // using '/bookingDetailsPage' continue to work.
          FFRoute(
            name: 'BookingDetailsPage',
            path: '/bookingDetailsPage',
            builder: (context, params) => BookingDetailsWidget(
              bookingId: params.getParam<String>('bookingId', ParamType.String),
              threadId: params.getParam<String>('threadId', ParamType.String),
              jobTitle: params.getParam<String>('jobTitle', ParamType.String),
              bookingPrice: params.getParam<String>('bookingPrice', ParamType.String),
              bookingDateTime: params.getParam<String>('bookingDateTime', ParamType.String),
              success: params.getParam<bool>('success', ParamType.bool),
            ),
          ),
        ];

        final goRoutes = ffRoutes.map((r) => r.toRoute()).toList();
        if (kDebugMode) {
          try {
            final registered = ffRoutes.map((r) => '${r.name}:${r.path}').join(', ');
            debugPrint('Registered routes: $registered');
          } catch (_) {}
        }

        return goRoutes;
      }(),
    );
}

extension NavParamExtensions on Map<String, String?> {
  Map<String, String> get withoutNulls => Map.fromEntries(
        entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );
}

extension NavigationExtensions on BuildContext {
  void safePop() {
    // If there is only one route on the stack, navigate to the initial
    // page instead of popping.
    if (canPop()) {
      pop();
    } else {
      go('/');
    }
  }
}

extension _GoRouterStateExtensions on GoRouterState {
  Map<String, dynamic> get extraMap =>
      extra != null ? extra as Map<String, dynamic> : {};
  Map<String, dynamic> get allParams => <String, dynamic>{}
    ..addAll(pathParameters)
    ..addAll(uri.queryParameters)
    ..addAll(extraMap);
  TransitionInfo get transitionInfo => extraMap.containsKey(kTransitionInfoKey)
      ? extraMap[kTransitionInfoKey] as TransitionInfo
      : TransitionInfo.appDefault();
}

class FFParameters {
  FFParameters(this.state, [this.asyncParams = const {}]);

  final GoRouterState state;
  final Map<String, Future<dynamic> Function(String)> asyncParams;

  Map<String, dynamic> futureParamValues = {};

  // Parameters are empty if the params map is empty or if the only parameter
  // present is the special extra parameter reserved for the transition info.
  bool get isEmpty =>
      state.allParams.isEmpty ||
      (state.allParams.length == 1 &&
          state.extraMap.containsKey(kTransitionInfoKey));
  bool isAsyncParam(MapEntry<String, dynamic> param) =>
      asyncParams.containsKey(param.key) && param.value is String;
  bool get hasFutures => state.allParams.entries.any(isAsyncParam);
  Future<bool> completeFutures() => Future.wait(
        state.allParams.entries.where(isAsyncParam).map(
          (param) async {
            final doc = await asyncParams[param.key]!(param.value)
                .onError((_, __) => null);
            if (doc != null) {
              futureParamValues[param.key] = doc;
              return true;
            }
            return false;
          },
        ),
      ).onError((_, __) => [false]).then((v) => v.every((e) => e));

  dynamic getParam<T>(
    String paramName,
    ParamType type, {
    bool isList = false,
  }) {
    if (futureParamValues.containsKey(paramName)) {
      return futureParamValues[paramName];
    }
    if (!state.allParams.containsKey(paramName)) {
      return null;
    }
    final param = state.allParams[paramName];
    // Got parameter from `extras`, so just directly return it.
    if (param is! String) {
      return param;
    }
    // Return serialized value.
    return deserializeParam<T>(
      param,
      type,
      isList,
    );
  }
}

class FFRoute {
  const FFRoute({
    required this.name,
    required this.path,
    required this.builder,
    this.requireAuth = false,
    this.requireNoAuth = false,
    this.asyncParams = const {},
    this.routes = const [],
  });

  final String name;
  final String path;
  final bool requireAuth;
  final bool requireNoAuth;
  final Map<String, Future<dynamic> Function(String)> asyncParams;
  final Widget Function(BuildContext, FFParameters) builder;
  final List<GoRoute> routes;

  GoRoute toRoute() => GoRoute(
        name: name,
        path: path,
        // Redirect based on auth state (synchronous check against AuthNotifier)
        redirect: (context, state) {
          try {
            // Do not block requireAuth routes at the router level. Guests may
            // navigate to pages like /profile or /home — feature-level checks
            // must guard actions. Only prevent already-authenticated users
            // from visiting no-auth pages (like login/register).
            if (requireNoAuth && AuthNotifier.instance.isAuthenticated) {
              return HomePageWidget.routePath;
            }
          } catch (e) {
            // ignore errors and allow normal routing
          }
          return null;
        },
         pageBuilder: (context, state) {
           fixStatusBarOniOS16AndBelow(context);
           final ffParams = FFParameters(state, asyncParams);
           final page = ffParams.hasFutures
               ? FutureBuilder(
                   future: ffParams.completeFutures(),
                   builder: (context, _) => builder(context, ffParams),
                 )
               : builder(context, ffParams);
          // Don't block rendering of routes for unauthenticated users here.
          // Protected actions must check `AuthNotifier.instance.isLoggedIn`
          // and navigate to the login page when required.
          final child = page;

            final transitionInfo = state.transitionInfo;
            return transitionInfo.hasTransition
                ? CustomTransitionPage(
                    key: state.pageKey,
                    child: child,
                    transitionDuration: transitionInfo.duration,
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) =>
                            PageTransition(
                      type: transitionInfo.transitionType,
                      duration: transitionInfo.duration,
                      reverseDuration: transitionInfo.duration,
                      alignment: transitionInfo.alignment,
                      child: child,
                    ).buildTransitions(
                      context,
                      animation,
                      secondaryAnimation,
                      child,
                    ),
                  )
                : MaterialPage(key: state.pageKey, child: child);
          },
          routes: routes,
        );
 }

/// A lightweight page that prompts unauthenticated users to sign in using the
/// existing `ensureAuthenticatedOrPrompt` bottom-sheet. After the user either
/// chooses to sign in or continue as guest, the protected route is dismissed so
/// they cannot access it.
class AuthRequiredGate extends StatefulWidget {
  const AuthRequiredGate({Key? key}) : super(key: key);

  @override
  _AuthRequiredGateState createState() => _AuthRequiredGateState();
}

class _AuthRequiredGateState extends State<AuthRequiredGate> {
  bool _prompted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prompted) {
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await ensureAuthenticatedOrPrompt(context,
              title: 'Sign in to continue',
              message: 'You must be signed in to view this page. Sign in now to gain full access.');
        } catch (_) {}
        // After prompt completes, dismiss this route — the user shouldn't
        // remain on the protected page when unauthenticated.
        try {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Render an empty scaffold while the prompt is presented.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(child: SizedBox.shrink()),
    );
  }
}

class TransitionInfo {
  const TransitionInfo({
    required this.hasTransition,
    this.transitionType = PageTransitionType.fade,
    this.duration = const Duration(milliseconds: 300),
    this.alignment,
  });

  final bool hasTransition;
  final PageTransitionType transitionType;
  final Duration duration;
  final Alignment? alignment;

  static TransitionInfo appDefault() => TransitionInfo(hasTransition: false);
}
