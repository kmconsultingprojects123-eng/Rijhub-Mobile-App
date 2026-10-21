import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/api/api_client.dart';
import '../data/api/api_context.dart';
import '../data/api/api_repositories.dart';
import '../data/api/api_social.dart';
import '../data/api/realtime.dart';
import '../data/api/token_store.dart';
import '../data/api/uploads.dart';
import '../data/mock/mock_market.dart';
import 'location.dart';
import 'media.dart';
import 'payments.dart';
import 'push.dart';
import '../data/mock/mock_repositories.dart';
import '../data/repositories/repositories.dart';

/// The one place that decides which implementation backs each repository:
/// [AppDependencies.api] for the RijHub API, [AppDependencies.mock] for
/// sample data (tests, and the app built without an API address).
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.catalog,
    required this.artisans,
    required this.jobs,
    required this.bookings,
    required this.artisanDashboard,
    required this.ask,
    required this.directory,
    required this.bookingFlow,
    required this.clientJobs,
    required this.quotes,
    required this.chat,
    required this.notices,
    required this.wallet,
    required this.account,
    required this.artisanSetup,
    required this.support,
    required this.media,
    required this.location,
    required this.push,
    this.payments = const SamplePaymentGateway(),
    this.sessionEnded = const Stream.empty(),
    this.hasSession = _always,
    this.startPush = _nothing,
  });

  static Future<bool> _always() async => true;
  static Future<void> _nothing() async {}

  /// Sample data. The mocks share one record of accounts, so bookings,
  /// earnings, requests and past hires belong to whoever is signed in, and
  /// a new account starts empty. With [live] on (the app), the mock also
  /// plays the other side a moment after each action: artisans accept,
  /// reply and quote. Tests turn it off.
  factory AppDependencies.mock({
    bool live = true,
    MediaService? media,
    LocationService? location,
    PushPermission? push,
  }) {
    final accounts = MockAccounts();
    final market = MockMarket(accounts, live: live);
    return AppDependencies(
      auth: MockAuthRepository(accounts: accounts),
      catalog: MockCatalogRepository(),
      artisans: MockArtisanRepository(accounts: accounts),
      jobs: MockJobRepository(accounts: accounts),
      bookings: MockBookingRepository(accounts: accounts),
      artisanDashboard: MockArtisanDashboardRepository(accounts: accounts),
      ask: MockAskRepository(market),
      directory: MockDirectoryRepository(market),
      bookingFlow: MockBookingFlowRepository(market),
      clientJobs: MockClientJobRepository(market),
      quotes: MockQuoteRepository(market),
      chat: MockChatRepository(market),
      notices: MockNoticeRepository(market),
      wallet: MockWalletRepository(market),
      account: MockAccountRepository(market),
      artisanSetup: MockArtisanSetupRepository(market),
      support: MockSupportRepository(),
      media: media ?? DeviceMediaService(),
      location: location ?? DeviceLocationService(),
      push: push ?? DevicePushPermission(),
    );
  }

  /// The RijHub API at [baseUrl] (its origin, for example
  /// `https://api.rijhub.com`). Payments open Paystack's checkout over the
  /// app's [navigator].
  factory AppDependencies.api({
    required Uri baseUrl,
    required GlobalKey<NavigatorState> navigator,
    TokenStore? tokens,
    MediaService? media,
    LocationService? location,
    PushPermission? push,
  }) {
    final api =
        ApiClient(baseUrl: baseUrl, tokens: tokens ?? SecureTokenStore());
    final payments = PaystackPaymentGateway(navigator);
    final c = ApiContext(
      api: api,
      uploads: Uploader(api),
      live: Realtime(api),
      checkout: payments.checkout,
    );
    final auth = ApiAuthRepository(c);
    final notifications = FirebasePush(
      permission: push ?? DevicePushPermission(),
      register: auth.registerDevice,
      signedIn: () => api.signedIn,
      navigator: navigator,
    );
    auth.onAccount = () => unawaited(notifications.sync());
    return AppDependencies(
      auth: auth,
      catalog: ApiCatalogRepository(c),
      artisans: ApiArtisanRepository(c),
      jobs: ApiJobRepository(c),
      bookings: ApiBookingRepository(c),
      artisanDashboard: ApiArtisanDashboardRepository(c),
      ask: ApiAskRepository(c),
      directory: ApiDirectoryRepository(c),
      bookingFlow: ApiBookingFlowRepository(c),
      clientJobs: ApiClientJobRepository(c),
      quotes: ApiQuoteRepository(c),
      chat: ApiChatRepository(c),
      notices: ApiNoticeRepository(c),
      wallet: ApiWalletRepository(c),
      account: ApiAccountRepository(c),
      artisanSetup: ApiArtisanSetupRepository(c),
      support: ApiSupportRepository(c),
      media: media ?? DeviceMediaService(),
      location: location ?? DeviceLocationService(),
      push: notifications,
      payments: payments,
      sessionEnded: api.sessionEnded,
      hasSession: () => api.signedIn,
      startPush: notifications.start,
    );
  }

  final AuthRepository auth;
  final CatalogRepository catalog;
  final ArtisanRepository artisans;
  final JobRepository jobs;
  final BookingRepository bookings;
  final ArtisanDashboardRepository artisanDashboard;
  final AskRepository ask;
  final DirectoryRepository directory;
  final BookingFlowRepository bookingFlow;
  final ClientJobRepository clientJobs;
  final QuoteRepository quotes;
  final ChatRepository chat;
  final NoticeRepository notices;
  final WalletRepository wallet;
  final AccountRepository account;
  final ArtisanSetupRepository artisanSetup;
  final SupportRepository support;

  /// The camera, microphone and speaker.
  final MediaService media;
  final LocationService location;
  final PushPermission push;

  /// How payments are taken: the app's pay sheet, or Paystack's checkout.
  final PaymentGateway payments;

  /// Fires when the server ends the session (signed out on every device,
  /// account deleted or suspended), so the app signs the person out.
  final Stream<void> sessionEnded;

  /// Whether a saved sign-in still has its session (the API's tokens).
  final Future<bool> Function() hasSession;

  /// Starts push notifications once the app is running: the app on the API
  /// only, after Firebase has started.
  final Future<void> Function() startPush;
}
