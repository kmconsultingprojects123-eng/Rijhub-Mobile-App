import '../models/models.dart';
import '../repositories/repositories.dart';
import 'mock_data.dart';

/// In-memory implementations of the repository contracts. Each call waits a
/// short, realistic moment so loading states get exercised.
Future<void> _latency([int ms = 450]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// What the mock backend knows while the app runs: the accounts that exist
/// (the samples, plus any created since launch), who is signed in, and
/// what has changed since launch. The mocks share one, so each answers for
/// the signed-in account, as a real backend would from its token.
class MockAccounts {
  /// The sample bookings and jobs are timed from [startedAt], so they come
  /// closer and grow older while the app runs, as real ones would.
  MockAccounts() : startedAt = DateTime.now();

  final DateTime startedAt;
  final _byPhone = Map<String, AppUser>.of(MockData.existingUsers);

  /// Bookings made since launch (accepted requests), by user id.
  final _newBookings = <String, List<Booking>>{};

  /// Who requests are for. Null while no one is signed in.
  AppUser? current;

  AppUser? withPhone(String phone) => _byPhone[phone];

  /// Records [user]'s account.
  void add(AppUser user) => _byPhone[user.phone] = user;

  /// The trades the signed-in artisan works in, as their account records
  /// them; empty for anyone else.
  List<String> get currentTrades {
    final user = current;
    if (user == null) return const [];
    return _byPhone[user.phone]?.tradeIds ?? user.tradeIds;
  }

  /// Bookings made since launch for account [userId].
  List<Booking> newBookingsOf(String? userId) =>
      _newBookings[userId] ?? const [];

  void addBooking(String userId, Booking booking) =>
      (_newBookings[userId] ??= []).add(booking);
}

class MockAuthRepository implements AuthRepository {
  MockAuthRepository({MockAccounts? accounts})
      : _accounts = accounts ?? MockAccounts();

  final MockAccounts _accounts;

  /// Entering this code simulates a wrong code.
  static const rejectedCode = '000000';

  @override
  Future<OtpChallenge> requestCode(
    String phone, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    await _latency(700);
    return OtpChallenge(
      phone: phone,
      channel: channel,
      requestId: 'otp_${phone.hashCode}',
      resendAvailableAt: DateTime.now().add(const Duration(seconds: 30)),
    );
  }

  @override
  Future<VerifyResult> verifyCode(OtpChallenge challenge, String code) async {
    await _latency(800);
    if (code == rejectedCode) {
      throw const AuthException(
        "That code isn't right. Check the message and try again.",
      );
    }
    return VerifyResult(user: _accounts.withPhone(challenge.phone));
  }

  @override
  Future<AppUser> createAccount({
    required String phone,
    required UserRole role,
    required String firstName,
    required String lastName,
    String? email,
    String? area,
    List<String> tradeIds = const [],
  }) async {
    await _latency(700);
    final user = AppUser(
      id: 'u_${phone.replaceAll('+', '')}',
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      role: role,
      email: email,
      homeArea: area,
      tradeIds: role == UserRole.artisan
          ? List.unmodifiable(tradeIds.toSet())
          : const [],
    );
    // The number now has an account, so signing in again finds it.
    _accounts.add(user);
    return user;
  }

  /// Also records the account, so one restored from an earlier launch
  /// signs back in like any other. An account the mock already knows keeps
  /// its record, which may be newer than the one saved on the device.
  @override
  void useAccount(AppUser user) {
    _accounts.current = user;
    if (_accounts.withPhone(user.phone) == null) _accounts.add(user);
  }

  @override
  Future<void> signOut() async {
    _accounts.current = null;
    await _latency(200);
  }
}

class MockCatalogRepository implements CatalogRepository {
  @override
  Future<List<ServiceCategory>> categories() async {
    await _latency(250);
    return MockData.categories;
  }

  @override
  Future<List<String>> areas() async {
    await _latency(150);
    return MockData.areas;
  }

  @override
  Future<List<PriceGuideItem>> priceGuide() async {
    await _latency(300);
    return MockData.priceGuide(DateTime.now());
  }
}

class MockArtisanRepository implements ArtisanRepository {
  MockArtisanRepository({MockAccounts? accounts})
      : _accounts = accounts ?? MockAccounts();

  final MockAccounts _accounts;

  /// Within this many km of a neighbourhood counts as near it.
  static const _nearKm = 10.0;

  @override
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  }) async {
    await _latency();
    final matching = [
      for (final artisan
          in MockData.artisansAt(_accounts.startedAt, area: area))
        if ((categoryId == null || artisan.categoryId == categoryId) &&
            (!freeNow || artisan.isAvailableToday))
          artisan,
    ];
    if (area == MockData.city) return matching.take(limit).toList();
    // Near ones first, still best rated first; then the rest, nearest
    // first, so a quiet area still shows someone.
    final near = matching.where((a) => a.distanceKm <= _nearKm);
    final far = matching.where((a) => a.distanceKm > _nearKm).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return [...near, ...far].take(limit).toList();
  }

  @override
  Future<List<HiredArtisan>> hiredBefore() async {
    final user = _accounts.current;
    await _latency(350);
    return MockData.hiredBeforeBy(
      user?.id,
      _accounts.startedAt,
      area: user?.area ?? MockData.city,
    );
  }
}

class MockJobRepository implements JobRepository {
  MockJobRepository({MockAccounts? accounts})
      : _accounts = accounts ?? MockAccounts();

  final MockAccounts _accounts;

  @override
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  }) async {
    final trades = _accounts.currentTrades;
    await _latency();
    final jobs = [
      for (final job in MockData.jobs(_accounts.startedAt, area: area))
        if (categoryIds == null ||
            categoryIds.isEmpty ||
            categoryIds.contains(job.categoryId))
          job,
    ];
    // Jobs in the signed-in artisan's trades come first, each group newest
    // first.
    bool inTrades(JobPost job) => trades.contains(job.categoryId);
    return [...jobs.where(inTrades), ...jobs.where((job) => !inTrades(job))]
        .take(limit)
        .toList();
  }

  @override
  Future<int> openJobsThisWeek({String? area, String? categoryId}) async {
    await _latency(300);
    return MockData.demand(area: area, categoryId: categoryId).openThisWeek;
  }

  @override
  Future<JobDemand> demand({String? area, String? categoryId}) async {
    await _latency(300);
    return MockData.demand(area: area, categoryId: categoryId);
  }
}

class MockBookingRepository implements BookingRepository {
  MockBookingRepository({MockAccounts? accounts})
      : _accounts = accounts ?? MockAccounts();

  final MockAccounts _accounts;

  /// A booking this long past its start is taken to be over.
  static const _lasts = Duration(hours: 2);

  @override
  Future<List<Booking>> upcoming({required UserRole as}) async {
    final user = _accounts.current;
    await _latency(350);
    final over = DateTime.now().subtract(_lasts);
    return [
      ...MockData.bookingsFor(user?.id, as, _accounts.startedAt),
      if (user != null && user.role == as) ..._accounts.newBookingsOf(user.id),
    ].where((b) => b.scheduledAt.isAfter(over)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }
}

class MockArtisanDashboardRepository implements ArtisanDashboardRepository {
  MockArtisanDashboardRepository({MockAccounts? accounts})
      : _accounts = accounts ?? MockAccounts();

  final MockAccounts _accounts;

  /// Dashboards changed since launch, by user id.
  final _changed = <String?, ArtisanDashboard>{};

  /// Each account's requests, made when first asked for, so their
  /// deadlines run from then; answered ones are removed.
  final _requests = <String?, List<DirectRequest>>{};

  ArtisanDashboard _dashboardOf(AppUser? user) {
    final dashboard = _changed[user?.id] ?? MockData.dashboardFor(user);
    final busyUntil = dashboard.busyUntil;
    // A busy spell ends by itself.
    if (busyUntil != null && !busyUntil.isAfter(DateTime.now())) {
      return dashboard.withAvailability(true);
    }
    return dashboard;
  }

  List<DirectRequest> _requestsOf(AppUser? user) => _requests[user?.id] ??=
      List.of(MockData.requestsFor(user?.id, DateTime.now()));

  @override
  Future<ArtisanDashboard> dashboard() async {
    final user = _accounts.current;
    await _latency();
    return _dashboardOf(user);
  }

  @override
  Future<void> setAvailability(bool available, {DateTime? busyUntil}) async {
    final user = _accounts.current;
    await _latency(300);
    _changed[user?.id] =
        _dashboardOf(user).withAvailability(available, busyUntil: busyUntil);
  }

  @override
  Future<List<DirectRequest>> requests() async {
    final user = _accounts.current;
    // Made before the wait, as a server would have it already.
    final pending = _requestsOf(user);
    await _latency(400);
    final now = DateTime.now();
    return pending.where((r) => r.expiresAt.isAfter(now)).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  }

  @override
  Future<Booking?> respond(String requestId, {required bool accept}) async {
    final user = _accounts.current;
    await _latency(500);
    final pending = _requestsOf(user);
    final index = pending.indexWhere((r) => r.id == requestId);
    if (index < 0) return null;
    final request = pending.removeAt(index);
    if (!request.expiresAt.isAfter(DateTime.now())) {
      throw const RequestExpiredException();
    }
    if (!accept || user == null) return null;
    final booking = Booking(
      id: 'b_${request.id}',
      serviceName: request.serviceName,
      categoryId: request.categoryId,
      scheduledAt: request.window.start,
      status: BookingStatus.confirmed,
      counterpartName: request.clientName,
      area: request.area,
      price: request.price,
    );
    _accounts.addBooking(user.id, booking);
    return booking;
  }
}
