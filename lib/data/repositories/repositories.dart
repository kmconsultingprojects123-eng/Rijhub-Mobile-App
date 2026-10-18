import 'package:flutter/foundation.dart';

import '../models/models.dart';

export 'market_repositories.dart';

/// Contracts between the UI and whatever backend serves it.
///
/// Screens depend only on these interfaces. Today they are backed by
/// `lib/data/mock/`; when the new RijHub backend is ready, add API-backed
/// implementations and swap them in `lib/app/dependencies.dart`. No screen
/// needs to change.
///
/// An `area` is a neighbourhood from [CatalogRepository.areas], or the
/// city's name ("Abuja") for all of it.

enum OtpChannel { sms, whatsapp }

@immutable
class OtpChallenge {
  const OtpChallenge({
    required this.phone,
    required this.channel,
    required this.requestId,
    required this.resendAvailableAt,
  });

  /// E.164.
  final String phone;
  final OtpChannel channel;
  final String requestId;
  final DateTime resendAvailableAt;
}

/// The result of checking a code. [user] is null when the phone number has
/// no account yet, so the app continues to profile setup.
@immutable
class VerifyResult {
  const VerifyResult({this.user});

  final AppUser? user;
  bool get isNewUser => user == null;
}

class AuthException implements Exception {
  const AuthException(this.message);

  /// Safe to show to the user.
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a direct request is answered after it expired.
class RequestExpiredException implements Exception {
  const RequestExpiredException([
    this.message = 'This request has expired, so the client has been '
        'offered other artisans.',
  ]);

  /// Safe to show to the user.
  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  Future<OtpChallenge> requestCode(
    String phone, {
    OtpChannel channel = OtpChannel.sms,
  });

  /// Throws [AuthException] when the code is wrong or expired.
  Future<VerifyResult> verifyCode(OtpChallenge challenge, String code);

  /// [area] is the neighbourhood the person picked before signing up, if
  /// any. An artisan's [tradeIds] are saved on the account
  /// ([AppUser.tradeIds]); a client's are ignored.
  Future<AppUser> createAccount({
    required String phone,
    required UserRole role,
    required String firstName,
    required String lastName,
    String? email,
    String? area,
    List<String> tradeIds = const [],
  });

  /// The app is signed in as [user] from now on: after a sign-in, and at
  /// launch with a saved session. Requests for the person's own data
  /// (bookings, earnings) are for this account. Implementations that keep a
  /// token load it here; the mock, which has none, remembers [user].
  void useAccount(AppUser user);

  /// Ends the session on the server. The device is signed out before this
  /// is called, so a failure (no connection) leaves no one signed in.
  Future<void> signOut();
}

abstract interface class CatalogRepository {
  Future<List<ServiceCategory>> categories();

  /// The neighbourhoods RijHub serves, in the order to list them.
  Future<List<String>> areas();

  /// What common jobs usually cost in Abuja, the most asked-about first.
  Future<List<PriceGuideItem>> priceGuide();

  /// How many ID-checked artisans RijHub has, and their average rating.
  Future<MarketStats> stats();
}

abstract interface class ArtisanRepository {
  /// The best-rated artisans for [area], best first; with a neighbourhood,
  /// those nearby come first. Narrowed to one trade by [categoryId], and
  /// to those free to take a job now by [freeNow].
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  });

  /// The artisans the signed-in client has hired before, most recent
  /// first. Empty for guests, artisans and clients who haven't hired yet.
  /// They may also appear in [topRatedNearby]; match them by id.
  Future<List<HiredArtisan>> hiredBefore();
}

abstract interface class JobRepository {
  /// Open jobs for [area], newest first, with the signed-in artisan's
  /// trades ahead of the rest. [categoryIds] keeps only those trades; null
  /// or empty keeps every trade.
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  });

  /// How many jobs posted this week are still open, in [area] (null or the
  /// city for all of Abuja), in one trade or in all.
  Future<int> openJobsThisWeek({String? area, String? categoryId});

  /// The same count, with jobs posted today and the usual budgets, for a
  /// demand line such as "46 AC repair jobs this week · most budgets
  /// ₦8,000 – ₦15,000".
  Future<JobDemand> demand({String? area, String? categoryId});
}

abstract interface class BookingRepository {
  /// The signed-in person's bookings that are still to come or under way,
  /// soonest first. Empty for guests and new accounts.
  Future<List<Booking>> upcoming({required UserRole as});
}

abstract interface class ArtisanDashboardRepository {
  Future<ArtisanDashboard> dashboard();

  /// Available now ([available] true), busy until [busyUntil] (then
  /// available again by itself), or off (neither).
  Future<void> setAvailability(bool available, {DateTime? busyUntil});

  /// Clients asking the signed-in artisan to take a job, soonest deadline
  /// first. Expired and answered ones are left out.
  Future<List<DirectRequest>> requests();

  /// Answers request [requestId]. Accepting books the job: it returns the
  /// new booking, which [BookingRepository.upcoming] now includes. Turning
  /// it down returns null, as does answering one already answered. Throws
  /// [RequestExpiredException] once it has expired.
  Future<Booking?> respond(String requestId, {required bool accept});
}
