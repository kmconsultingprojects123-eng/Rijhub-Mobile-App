import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/account/account_pages.dart';
import '../features/account/account_tab.dart';
import '../data/models/models.dart';
import '../features/artisan/business_pages.dart';
import '../features/artisan/money_pages.dart';
import '../features/artisan/verification_screen.dart';
import '../features/artisan/work_screens.dart';
import '../features/artisan_profile/artisan_profile_screen.dart';
import '../features/ask/ask_launch.dart';
import '../features/ask/ask_screen.dart';
import '../features/booking/booking_screen.dart';
import '../features/bookings/bookings_tab.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/jobs/client_job_screen.dart';
import '../features/jobs/post_job_screen.dart';
import '../features/messages/chat_screen.dart';
import '../features/messages/messages_tab.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/discover_tab.dart';
import '../features/shared/page.dart';
import '../data/repositories/repositories.dart';
import '../features/support/support_screens.dart';
import 'routes.dart';
import 'session.dart';

export 'routes.dart';

GoRouter buildRouter(
  SessionController session, {
  String? initialLocation,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  GoRoute page(String path, Widget Function(GoRouterState state) build) =>
      GoRoute(path: path, builder: (context, state) => build(state));

  return GoRouter(
    navigatorKey: navigatorKey,
    // A first open starts with the welcome conversation; after that, home.
    initialLocation: initialLocation ??
        (session.hasOnboarded ? Routes.home : Routes.welcome),
    // Not refreshed when the session changes: screens navigate after the
    // change they cause, so a sign-in can finish its success moment first.
    debugLogDiagnostics: kDebugMode,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => SplashScreen(
          hold: kDebugMode && state.uri.queryParameters['hold'] == '1',
        ),
      ),
      // The first open: a conversation with RijHub, with "I'm an artisan"
      // and "Look around" as the other ways in.
      page(Routes.welcome,
          (s) => const AskScreen(launch: AskLaunch(start: AskStart.welcome))),
      page(
          Routes.ask,
          (s) => AskScreen(
              launch: s.extra is AskLaunch
                  ? s.extra! as AskLaunch
                  : const AskLaunch())),
      page(Routes.map,
          (s) => const ExploreScreen(startOnMap: true, standalone: true)),
      page('/artisan/:id',
          (s) => ArtisanProfileScreen(artisanId: s.pathParameters['id']!)),
      page('/artisan/:id/reviews',
          (s) => ReviewsScreen(artisanId: s.pathParameters['id']!)),
      page(
          '/artisan/:id/work',
          (s) => WorkGalleryScreen(
                artisanId: s.pathParameters['id']!,
                initial: int.tryParse(s.uri.queryParameters['i'] ?? '') ?? 0,
              )),
      page(
          '/book/:id',
          (s) =>
              AskScreen(launch: AskLaunch(artisanId: s.pathParameters['id']))),
      page('/booking/:id',
          (s) => BookingScreen(bookingId: s.pathParameters['id']!)),
      page('/jobs/:id', (s) => ClientJobScreen(jobId: s.pathParameters['id']!)),
      page(Routes.postJob, (s) => const PostJobScreen()),
      page(
          '/jobs/:id/edit',
          (s) => _EditJob(
              jobId: s.pathParameters['id']!,
              job: s.extra is ClientJob ? s.extra! as ClientJob : null)),
      page('/chat/:id',
          (s) => ChatScreen(conversationId: s.pathParameters['id']!)),
      page(Routes.notifications, (s) => const NotificationsScreen()),
      page(Routes.editProfile, (s) => const EditProfileScreen()),
      page(Routes.saved, (s) => const SavedScreen()),
      page(Routes.places, (s) => const PlacesScreen()),
      page(Routes.myJobs, (s) => const MyJobsScreen()),
      page(Routes.payments, (s) => const PaymentsScreen()),
      page(Routes.settings, (s) => const SettingsScreen()),
      page(Routes.notificationSettings,
          (s) => const NotificationSettingsScreen()),
      page(Routes.about, (s) => const AboutScreen()),
      page(Routes.deleteAccount, (s) => const DeleteAccountScreen()),
      page(Routes.myProfile,
          (s) => ArtisanProfileScreen(artisanId: 'me', preview: true)),
      page(Routes.reviews,
          (s) => const ReviewsScreen(artisanId: 'me', own: true)),
      page(Routes.support, (s) => const HelpCentreScreen()),
      page(
          '/support/faq/:id', (s) => FaqScreen(faqId: s.pathParameters['id']!)),
      page(Routes.voiceSupport, (s) => const VoiceSupportScreen()),
      page('/requests/:id',
          (s) => RequestScreen(requestId: s.pathParameters['id']!)),
      page(
          '/quote-requests/:id',
          (s) => ArtisanJobScreen(
              jobId: s.pathParameters['id']!, priceRequest: true)),
      page('/job/:id', (s) => ArtisanJobScreen(jobId: s.pathParameters['id']!)),
      page(
          '/job/:id/quote',
          (s) => SendQuoteScreen(
              jobId: s.pathParameters['id']!,
              job: s.extra is JobPost ? s.extra! as JobPost : null)),
      page(Routes.services, (s) => const ServicesScreen()),
      page(Routes.portfolio, (s) => const PortfolioScreen()),
      page(Routes.workArea, (s) => const WorkAreaScreen()),
      page(Routes.hours, (s) => const HoursScreen()),
      page(Routes.verification, (s) => const VerificationScreen()),
      page(Routes.wallet, (s) => const WalletScreen()),
      page(Routes.payoutAccount, (s) => const PayoutAccountScreen()),
      page(Routes.withdraw, (s) => const WithdrawScreen()),
      page(Routes.quotes, (s) => const MyQuotesScreen()),
      page(Routes.terms, (s) => const LegalScreen(privacy: false)),
      page(Routes.privacy, (s) => const LegalScreen(privacy: true)),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            _fade(state, AppShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.explore,
              builder: (context, state) => DiscoverTab(
                categoryId: state.uri.queryParameters['category'],
                map: state.uri.queryParameters['map'] == '1',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.bookings,
                builder: (context, state) => const BookingsTab()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.messages,
                builder: (context, state) => const MessagesTab()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.account,
                builder: (context, state) => const AccountTab()),
          ]),
        ],
      ),
    ],
  );
}

/// The job form, filled in with [job], fetched when opened from a link.
class _EditJob extends StatelessWidget {
  const _EditJob({required this.jobId, this.job});

  final String jobId;
  final ClientJob? job;

  @override
  Widget build(BuildContext context) {
    final known = job;
    if (known != null) return PostJobScreen(editing: known);
    return Loader<ClientJob>(
      load: () => context.read<ClientJobRepository>().byId(jobId),
      builder: (context, job, _) => PostJobScreen(editing: job),
    );
  }
}

/// Arriving from the splash cross-fades rather than sliding sideways,
/// because it isn't a step "forward".
Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );
