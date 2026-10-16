// The artisan home: the area it shows, what comes first on the dashboard,
// availability, requests, hiding earnings, honest numbers for new accounts,
// and the job rows and job sheet.
//
// The mock repositories wait with Future.delayed, which completes when the
// test pumps fake time past it, so tests pump rather than await them.
//
// The sample bookings and request are timed from the real clock, so these
// tests check what holds at any time of day.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/home/artisan_home_screen.dart';
import 'package:rijhub/features/home/home_screen.dart';
import 'package:rijhub/features/home/widgets/artisan_availability_sheet.dart';
import 'package:rijhub/features/home/widgets/artisan_format.dart';
import 'package:rijhub/features/home/widgets/artisan_home_rows.dart';
import 'package:rijhub/features/home/widgets/artisan_job_row.dart';
import 'package:rijhub/features/home/widgets/artisan_request_card.dart';
import 'package:rijhub/features/home/widgets/artisan_section_label.dart';
import 'package:rijhub/features/home/widgets/artisan_today_card.dart';
import 'package:rijhub/features/home/widgets/artisan_top_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _emeka = MockData.sampleUser(UserRole.artisan);

/// A brand-new artisan, who has no bookings, earnings or reviews.
const _newArtisan = AppUser(
  id: 'u_new_artisan',
  firstName: 'Bala',
  lastName: 'Usman',
  phone: '+2348091234567',
  role: UserRole.artisan,
);

/// The mock's jobs, recording the areas asked for.
class _SpyJobs implements JobRepository {
  final _inner = MockJobRepository();
  final areas = <String>[];

  @override
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  }) {
    areas.add(area);
    return _inner.openJobsNearby(
      area: area,
      categoryIds: categoryIds,
      limit: limit,
    );
  }

  @override
  Future<int> openJobsThisWeek({String? area, String? categoryId}) =>
      _inner.openJobsThisWeek(area: area, categoryId: categoryId);

  @override
  Future<JobDemand> demand({String? area, String? categoryId}) =>
      _inner.demand(area: area, categoryId: categoryId);
}

/// Jobs a test supplies, with demand figures no test here reads.
abstract class _FakeJobs implements JobRepository {
  @override
  Future<int> openJobsThisWeek({String? area, String? categoryId}) async => 0;

  @override
  Future<JobDemand> demand({String? area, String? categoryId}) async =>
      const JobDemand(openThisWeek: 0, postedToday: 0);
}

/// The mock's catalog, counting loads of trades.
class _SpyCatalog implements CatalogRepository {
  final _inner = MockCatalogRepository();
  var tradeLoads = 0;

  @override
  Future<List<ServiceCategory>> categories() {
    tradeLoads++;
    return _inner.categories();
  }

  @override
  Future<List<String>> areas() => _inner.areas();

  @override
  Future<List<PriceGuideItem>> priceGuide() => _inner.priceGuide();
}

/// Answers for Abuja only when told to, and for anywhere else at once.
class _RacingJobs extends _FakeJobs {
  final abuja = Completer<List<JobPost>>();

  @override
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  }) =>
      area == 'Abuja'
          ? abuja.future
          : Future.value([_job('new', 'Fix a leaking tap in Gwarinpa')]);
}

/// A catalog whose ids differ from its icon keys, as a backend's may.
class _KeyedCatalog implements CatalogRepository {
  @override
  Future<List<ServiceCategory>> categories() async =>
      const [ServiceCategory(id: 'cat_7', name: 'AC repair', iconKey: 'ac')];

  @override
  Future<List<String>> areas() async => const [];

  @override
  Future<List<PriceGuideItem>> priceGuide() async => const [];
}

class _OneAcJob extends _FakeJobs {
  @override
  Future<List<JobPost>> openJobsNearby({
    required String area,
    Set<String>? categoryIds,
    int limit = 10,
  }) async =>
      [_job('j', 'Fix my AC', categoryId: 'cat_7')];
}

/// The mock dashboard, except that saving availability fails.
class _NoSaving extends MockArtisanDashboardRepository {
  _NoSaving({super.accounts});

  @override
  Future<void> setAvailability(bool available, {DateTime? busyUntil}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    throw Exception('offline');
  }
}

/// The mock dashboard, except that answers to requests fail to send.
class _NoAnswers extends MockArtisanDashboardRepository {
  _NoAnswers({super.accounts});

  @override
  Future<Booking?> respond(String requestId, {required bool accept}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    throw Exception('offline');
  }
}

/// One booking, half an hour into the time the sample request asks for.
class _BookedInTheWindow implements BookingRepository {
  @override
  Future<List<Booking>> upcoming({required UserRole as}) async {
    final now = DateTime.now();
    // The sample request's window starts on the hour, two hours ahead.
    final start = DateTime(now.year, now.month, now.day, now.hour + 2);
    return [
      Booking(
        id: 'b_clash',
        serviceName: 'Generator service',
        categoryId: 'generator',
        scheduledAt: start.add(const Duration(minutes: 30)),
        status: BookingStatus.confirmed,
        counterpartName: 'Tunde Bakare',
        area: 'Jabi',
      ),
    ];
  }
}

JobPost _job(String id, String title, {String categoryId = 'plumbing'}) =>
    JobPost(
      id: id,
      title: title,
      categoryId: categoryId,
      area: 'Jabi',
      distanceKm: 2.4,
      postedAt: DateTime.now(),
    );

/// The home as the tests drive it.
class _Home {
  _Home(this.session, this.prefs, this.deps, this.prompts);

  final SessionController session;
  final SharedPreferences prefs;
  final AppDependencies deps;

  /// What the sign-in gate was asked for.
  final List<AuthPrompt> prompts;
}

/// Shows [screen] (the artisan home) on a phone [height] points tall, to a
/// guest artisan or [user], in [area] if given, on mock data except for
/// the repositories passed. [prefs] carries a device over from an earlier
/// pump. Call [_wait] to let it load.
Future<_Home> _pump(
  WidgetTester t, {
  AppUser? user,
  String? area,
  JobRepository? jobs,
  CatalogRepository? catalog,
  BookingRepository? bookings,
  ArtisanDashboardRepository Function(MockAccounts accounts)? dashboard,
  AuthPresenter? presenter,
  Widget screen = const ArtisanHomeScreen(),
  double height = 844,
  SharedPreferences? prefs,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(390 * 3, height * 3);
  addTearDown(t.view.reset);
  if (prefs == null) {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }
  final accounts = MockAccounts();
  final deps = AppDependencies(
    auth: MockAuthRepository(accounts: accounts),
    catalog: catalog ?? MockCatalogRepository(),
    artisans: MockArtisanRepository(accounts: accounts),
    jobs: jobs ?? MockJobRepository(accounts: accounts),
    bookings: bookings ?? MockBookingRepository(accounts: accounts),
    artisanDashboard: dashboard?.call(accounts) ??
        MockArtisanDashboardRepository(accounts: accounts),
  );
  final session = SessionController(prefs: prefs, auth: deps.auth);
  await session.continueAsGuest(UserRole.artisan);
  if (area != null) await session.setArea(area);
  if (user != null) await session.signIn(user);
  final prompts = <AuthPrompt>[];
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => screen),
      GoRoute(
        path: '/:rest',
        builder: (context, state) =>
            Scaffold(body: Text('Went to ${state.uri}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(MultiProvider(
    providers: [
      Provider<AuthRepository>.value(value: deps.auth),
      Provider<CatalogRepository>.value(value: deps.catalog),
      Provider<ArtisanRepository>.value(value: deps.artisans),
      Provider<JobRepository>.value(value: deps.jobs),
      Provider<BookingRepository>.value(value: deps.bookings),
      Provider<ArtisanDashboardRepository>.value(
        value: deps.artisanDashboard,
      ),
      Provider<AuthGate>.value(
        value: AuthGate(
          presenter ??
              (context, prompt) async {
                prompts.add(prompt);
                return false;
              },
        ),
      ),
      ChangeNotifierProvider.value(value: session),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  ));
  return _Home(session, prefs, deps, prompts);
}

/// Pumps [total] of fake time in short frames, so mock latencies and
/// animations run.
Future<void> _wait(
  WidgetTester t, [
  Duration total = const Duration(milliseconds: 1200),
]) async {
  const frame = Duration(milliseconds: 100);
  for (var waited = Duration.zero; waited < total; waited += frame) {
    await t.pump(frame);
  }
}

/// Waits for [future] from a mock, pumping fake time past its latency.
Future<T> _await<T>(WidgetTester t, Future<T> future) async {
  await _wait(t, const Duration(milliseconds: 800));
  return future;
}

/// Lays text out in Inter, as on a device. The test font's wider glyphs
/// would wrap titles that fit on one line in the real one.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await loader.load();
}

Finder _pill(String place) => find.bySemanticsLabel('Area: $place. Change');

/// The availability pill, saying [state].
Finder _availability(String state) =>
    find.bySemanticsLabel(RegExp('^Availability\\. $state'));

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

double _top(WidgetTester t, Finder finder) => t.getRect(finder).top;

void main() {
  setUpAll(_loadInter);

  group('Area', () {
    testWidgets('with no area, a guest sees Abuja and no distances', (t) async {
      await _pump(t, height: 2400);
      await _wait(t);
      expect(_pill('Abuja'), findsOneWidget);
      expect(find.text('Jobs near you'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
      final demand = MockData.demand();
      expect(
        find.text('${demand.openThisWeek} open jobs in Abuja this week'),
        findsOneWidget,
      );
      expect(
        find.text('Most budgets ${ArtisanFormat.budget(
          demand.typicalBudgetMin,
          demand.typicalBudgetMax,
        )}'),
        findsOneWidget,
      );
      // Read in the order the row shows it, with the time mid-sentence.
      expect(
        find.bySemanticsLabel(RegExp(
          r'^AC not cooling and leaking water\. Budget ₦8,000 to ₦12,000\. '
          r'Garki Area 11\. Urgent\. Posted 12 minutes ago\. ',
        )),
        findsOneWidget,
      );
    });

    testWidgets('with an area, jobs are near you and give distances',
        (t) async {
      await _pump(t, area: 'Gwarinpa', height: 2400);
      await _wait(t);
      expect(_pill('Gwarinpa'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d\.\d km')), findsWidgets);
      expect(
        find.text(
          '${MockData.demand(area: 'Gwarinpa').openThisWeek} open jobs near '
          'Gwarinpa this week',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'the pill opens the picker, and a new area reloads only the jobs',
        (t) async {
      final jobs = _SpyJobs();
      final catalog = _SpyCatalog();
      final home = await _pump(t, jobs: jobs, catalog: catalog);
      await _wait(t);
      await t.tap(find.widgetWithText(AppChip, 'AC repair'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Socket sparking in the kitchen'), findsNothing);
      final asked = jobs.areas.length;

      await t.tap(_pill('Abuja'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text("We'll show you jobs nearby."), findsOneWidget);
      await t.enterText(find.byType(TextField), 'gwar');
      await t.pump();
      await t.tap(_inSheet(find.text('Gwarinpa')));
      await _wait(t);

      expect(home.session.area, 'Gwarinpa');
      expect(_pill('Gwarinpa'), findsOneWidget);
      // One new request, for the new area.
      expect(jobs.areas.skip(asked), ['Gwarinpa']);
      expect(catalog.tradeLoads, 1, reason: 'trades stay loaded');
      expect(
        t.widget<AppChip>(find.widgetWithText(AppChip, 'AC repair')).selected,
        isTrue,
        reason: 'the trade filter stays',
      );
      expect(find.text('Service two split AC units'), findsOneWidget);
      expect(find.text('Socket sparking in the kitchen'), findsNothing);
      expect(
        find.text(
          '${MockData.demand(area: 'Gwarinpa', categoryId: 'ac').openThisWeek}'
          ' AC repair jobs this week',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a late reply for the old area is dropped', (t) async {
      final jobs = _RacingJobs();
      final home = await _pump(t, jobs: jobs);
      await _wait(t);
      await home.session.setArea('Gwarinpa');
      await _wait(t);
      expect(find.text('Fix a leaking tap in Gwarinpa'), findsOneWidget);

      jobs.abuja.complete([_job('old', 'A job from the old area')]);
      await _wait(t);
      expect(find.text('A job from the old area'), findsNothing);
      expect(find.text('Fix a leaking tap in Gwarinpa'), findsOneWidget);
    });

    testWidgets("availability's sheet counts today's jobs near the area",
        (t) async {
      await _pump(t, user: _emeka, area: 'Garki');
      await _wait(t);
      expect(_pill('Garki'), findsNothing, reason: 'signed in: no pill');
      await t.tap(_availability('Available'));
      await _wait(t, const Duration(milliseconds: 600));
      final today =
          MockData.demand(area: 'Garki', categoryId: 'ac').postedToday;
      expect(
        _inSheet(find.text('$today AC repair jobs posted today near Garki')),
        findsOneWidget,
      );
    });

    testWidgets('with no area, the count is for all of Abuja', (t) async {
      await _pump(t, user: _newArtisan);
      await _wait(t);
      await t.tap(_availability('Off'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(
        _inSheet(find.text(
          '${MockData.demand().postedToday} jobs posted today in Abuja',
        )),
        findsOneWidget,
      );
    });
  });

  group('Dashboard', () {
    testWidgets('puts the work first: today, requests, then new jobs',
        (t) async {
      await _pump(t, user: _emeka, height: 2400);
      await _wait(t);
      final today = _top(t, find.byType(ArtisanTodayCard));
      final request = _top(t, find.byType(ArtisanRequestCard));
      final jobs = _top(t, find.text('New jobs for you'));
      final week = _top(t, find.byType(ArtisanWeekRow));
      final setup = _top(t, find.byType(ArtisanSetupRow));
      expect(today, lessThan(request));
      expect(request, lessThan(jobs));
      expect(jobs, lessThan(week));
      expect(week, lessThan(setup));
      // The next job, read as one sentence. It starts a little over an
      // hour from now.
      expect(
        find.bySemanticsLabel(RegExp(
          r'^Next job, \d{1,2}:\d{2}\s[AP]M, in 1 hour( \d+ minutes?)?: AC '
          r'servicing for Chidinma O\., Wuse 2, near Banex Plaza, 3\.1 '
          r'kilometres away\.',
        )),
        findsOneWidget,
      );
      // No avatar and no greeting: the Profile tab says who they are.
      expect(find.textContaining('Emeka'), findsNothing);
      expect(find.byType(AppAvatar), findsNothing);
    });

    testWidgets('the top bar is two pills and the bell', (t) async {
      await _pump(t, user: _emeka);
      await _wait(t);
      final bar = t.getRect(find.byType(ArtisanTopBar));
      expect(bar.height, closeTo(56, 0.5));
      final pill = t.getRect(
        find
            .descendant(
              of: find.byType(ArtisanAvailabilityPill),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(pill.height, closeTo(40, 0.5));
      expect(
        t.getRect(find.byType(ArtisanAvailabilityPill)).height,
        AppSize.minTapTarget,
      );
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('₦86,500'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Notifications'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(
        find.text('Notifications are next in the redesign.'),
        findsOneWidget,
      );
    });

    testWidgets('earnings can be hidden, and stay hidden next time', (t) async {
      final home = await _pump(t, user: _emeka);
      await _wait(t);
      expect(find.text('₦86,500'), findsOneWidget);

      await t.tap(
        find.bySemanticsLabel('Earned this week: ₦86,500. Hide the amount'),
      );
      await t.pump();
      expect(find.text('₦86,500'), findsNothing);
      expect(find.text('₦ •••••'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Earned this week: hidden. Show the amount'),
        findsOneWidget,
      );
      expect(home.prefs.getBool('dashboard.hideEarnings'), isTrue);

      // The next launch keeps them hidden from the first frame.
      await _pump(t, user: _emeka, prefs: home.prefs);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('₦86,500'), findsNothing);
      }
      await t.tap(
        find.bySemanticsLabel('Earned this week: hidden. Show the amount'),
      );
      await t.pump();
      expect(find.text('₦86,500'), findsOneWidget);
      expect(home.prefs.getBool('dashboard.hideEarnings'), isFalse);
    });

    testWidgets('the week shows the star first and the review count',
        (t) async {
      await _pump(t, user: _emeka, height: 2400);
      await _wait(t);
      expect(find.text('★ 4.9 (128)'), findsOneWidget);
      expect(find.text('replies 96%'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'This week: 6 jobs, rated 4.9 out of 5 from 128 reviews, replies '
          'to 96% of requests',
        ),
        findsOneWidget,
      );
      await t.tap(find.byType(ArtisanWeekRow));
      await _wait(t, const Duration(milliseconds: 300));
      expect(
        find.text('Earnings and stats are next in the redesign.'),
        findsOneWidget,
      );
    });

    testWidgets('a new artisan sees no rate or earnings they never had',
        (t) async {
      await _pump(t, user: _newArtisan, height: 2400);
      await _wait(t);
      // Off until set up, and no money pill until there is money.
      expect(_availability('Off'), findsOneWidget);
      expect(find.byType(ArtisanWalletPill), findsNothing);
      expect(find.textContaining('₦0'), findsNothing);
      // No week to sum up, no day to plan, no requests.
      expect(find.byType(ArtisanWeekRow), findsNothing);
      expect(find.textContaining('0%'), findsNothing);
      expect(find.byType(ArtisanTodayCard), findsNothing);
      expect(find.byType(ArtisanNothingToday), findsNothing);
      expect(find.byType(ArtisanRequestCard), findsNothing);
      // The ID check comes first, as a banner; the rest of setup waits
      // below the jobs.
      expect(
        find.text('Verify your ID to start getting booked'),
        findsOneWidget,
      );
      expect(find.text('2 minutes · NIN + selfie'), findsOneWidget);
      expect(
        _top(t, find.byType(ArtisanSetupBanner)),
        lessThan(_top(t, find.text('New jobs for you'))),
      );
      expect(find.byType(ArtisanSetupRow), findsOneWidget);
      expect(find.text('Set your work area'), findsOneWidget);
      await t.tap(find.text('Start'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(find.text('ID checks are next in the redesign.'), findsOneWidget);
    });

    testWidgets('"Schedule" and "See all" take taps around their rows',
        (t) async {
      // "Schedule" takes taps in the gaps above and below its 24pt row...
      for (final offset in [-3.0, 6.0]) {
        await _pump(t, user: _emeka, height: 2400);
        await _wait(t);
        final link = find.text('Schedule');
        final row = t.getRect(
          find.ancestor(of: link, matching: find.byType(ArtisanSectionLabel)),
        );
        final x = t.getCenter(link).dx;
        await t.tapAt(
          Offset(x, offset < 0 ? row.top + offset : row.bottom + offset),
        );
        await _wait(t, const Duration(milliseconds: 600));
        expect(find.text('Went to /bookings'), findsOneWidget);
      }
      // ...and "See all", whose chips start right under it, in the gap
      // above.
      for (final above in [8.0, 20.0]) {
        await _pump(t, user: _emeka, height: 2400);
        await _wait(t);
        final link = find.text('See all');
        final row = t.getRect(
          find.ancestor(of: link, matching: find.byType(ArtisanSectionHeader)),
        );
        await t.tapAt(Offset(t.getCenter(link).dx, row.top - above));
        await _wait(t, const Duration(milliseconds: 600));
        expect(find.text('Went to /explore'), findsOneWidget);
      }
    });
  });

  group('Availability', () {
    testWidgets('can be busy until a chosen end, then off, then available',
        (t) async {
      final home = await _pump(t, user: _emeka);
      await _wait(t);
      await t.tap(_availability('Available'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Your availability')), findsOneWidget);

      await t.tap(_inSheet(find.text('Busy until…')));
      await t.pump();
      final ends = _inSheet(find.byType(AppChip));
      expect(ends, findsNWidgets(3));
      final labels = [
        for (final chip in t.widgetList<AppChip>(ends)) chip.label,
      ];
      // One, two and three hours away, on the quarter hour.
      final soon = DateTime.now();
      for (final (i, hours) in [1, 2, 3].indexed) {
        expect(
          labels[i],
          ArtisanFormat.clock(
            ArtisanAvailabilitySheet.busyFor(hours, from: soon),
          ),
        );
      }
      await t.tap(ends.at(1));
      await _wait(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Busy till ${labels[1]}'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Availability. Busy until ${labels[1]}. Change'),
        findsOneWidget,
      );
      var saved = await _await(t, home.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.busy);

      await t.tap(find.text('Busy till ${labels[1]}'));
      await _wait(t, const Duration(milliseconds: 600));
      // Busy now: the option says until when, and the ends stay open.
      expect(_inSheet(find.text('Busy until ${labels[1]}')), findsOneWidget);
      await t.tap(_inSheet(find.text('Off')));
      await _wait(t);
      expect(_availability('Off'), findsOneWidget);
      saved = await _await(t, home.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.off);

      await t.tap(_availability('Off'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.tap(_inSheet(find.text('Available now')));
      await _wait(t);
      expect(_availability('Available'), findsOneWidget);
      saved = await _await(t, home.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.available);
    });

    testWidgets('a change that fails to save is put back, and says so',
        (t) async {
      await _pump(t, user: _emeka, dashboard: (a) => _NoSaving(accounts: a));
      await _wait(t);
      await t.tap(_availability('Available'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.tap(_inSheet(find.text('Off')));
      await t.pump();
      // Shown at once...
      expect(_availability('Off'), findsOneWidget);
      await _wait(t);
      // ...and back when the save fails.
      expect(_availability('Available'), findsOneWidget);
      expect(
        find.text("We couldn't update your availability. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('waits for the ID check before clients can book', (t) async {
      await _pump(t, user: _newArtisan);
      await _wait(t);
      await t.tap(_availability('Off'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Verify your ID first')), findsOneWidget);
      // The options wait for it.
      await t.tap(_inSheet(find.text('Available now')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(_availability('Off'), findsOneWidget);

      await t.tap(_inSheet(find.text('Verify your ID')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('ID checks are next in the redesign.'), findsOneWidget);
    });
  });

  group('Requests', () {
    testWidgets('say who, what, when, where and the price, with a countdown',
        (t) async {
      await _pump(t, user: _emeka, height: 2400);
      await _wait(t);
      expect(find.text('REQUESTS FOR YOU · 1'), findsOneWidget);
      expect(find.text('Ngozi A. wants to book you'), findsOneWidget);
      expect(find.text('14 min'), findsOneWidget);
      expect(find.text('Socket repair'), findsOneWidget);
      expect(find.text('₦6,000'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(
          r'^Ngozi A\. wants to book you: Socket repair, (today|tomorrow) '
          r'.+, Wuse 2, ₦6,000\. 14 minutes left to answer\.',
        )),
        findsOneWidget,
      );
      // One strong action; "Not now" is quiet.
      expect(find.widgetWithText(AppButton, 'Accept'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Not now'), findsNothing);
      expect(
        find.bySemanticsLabel("Not now: turn down Ngozi A.'s request"),
        findsOneWidget,
      );
    });

    testWidgets('Accept books it and takes the card away', (t) async {
      final home = await _pump(t, user: _emeka, height: 2400);
      await _wait(t);
      await t.tap(find.widgetWithText(AppButton, 'Accept'));
      await t.pump();
      // Both answers wait while this one is sent.
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, 'Accept')).onPressed,
        isNull,
      );
      await _wait(t);
      expect(find.byType(ArtisanRequestCard), findsNothing);
      expect(find.text('REQUESTS FOR YOU · 1'), findsNothing);
      expect(find.text("Booked. It's in your schedule."), findsOneWidget);
      final booked = await _await(
        t,
        home.deps.bookings.upcoming(as: UserRole.artisan),
      );
      expect(booked.map((b) => b.serviceName), contains('Socket repair'));
    });

    testWidgets('"Not now" takes it away without a word', (t) async {
      final home = await _pump(t, user: _emeka, height: 2400);
      await _wait(t);
      await t.tap(
        find.bySemanticsLabel("Not now: turn down Ngozi A.'s request"),
      );
      // It folds away at once, without waiting for the server.
      await _wait(t, const Duration(milliseconds: 400));
      expect(find.byType(ArtisanRequestCard), findsNothing);
      await _wait(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(await _await(t, home.deps.artisanDashboard.requests()), isEmpty);
    });

    testWidgets('an answer that fails to send puts the request back',
        (t) async {
      await _pump(
        t,
        user: _emeka,
        height: 2400,
        dashboard: (a) => _NoAnswers(accounts: a),
      );
      await _wait(t);
      await t.tap(
        find.bySemanticsLabel("Not now: turn down Ngozi A.'s request"),
      );
      await _wait(t);
      expect(find.byType(ArtisanRequestCard), findsOneWidget);
      expect(
        find.text("We couldn't send your answer. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('a clash with a booking is said before accepting', (t) async {
      await _pump(
        t,
        user: _emeka,
        height: 2400,
        bookings: _BookedInTheWindow(),
      );
      await _wait(t);
      final booking = (await _await(
        t,
        _BookedInTheWindow().upcoming(as: UserRole.artisan),
      ))
          .single;
      final clash =
          'Clashes with your ${ArtisanFormat.clock(booking.scheduledAt)} job';
      expect(find.text(clash), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('${RegExp.escape(clash)}\\.\$')),
        findsOneWidget,
      );
    });
  });

  group('Job rows', () {
    testWidgets('urgent jobs use a stopwatch, not the electrical bolt',
        (t) async {
      await _pump(t, height: 2400);
      await _wait(t);
      expect(
        find.descendant(
          of: find.byType(ArtisanJobRow),
          matching: find.byIcon(IconsaxPlusBold.timer_1),
        ),
        findsNWidgets(2),
      );
      expect(find.byIcon(IconsaxPlusBold.flash_1), findsNothing);
    });

    for (final user in [null, _emeka]) {
      testWidgets(
          'icons come from the trade, not its id '
          '(${user == null ? 'guest' : 'dashboard'})', (t) async {
        await _pump(
          t,
          user: user,
          jobs: _OneAcJob(),
          catalog: _KeyedCatalog(),
          height: 2400,
        );
        await _wait(t);
        expect(
          find.descendant(
            of: find.byType(ArtisanJobRow),
            matching: find.byIcon(IconsaxPlusLinear.wind),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('are 88pt flat rows with no buttons of their own', (t) async {
      await _pump(t, height: 2400);
      await _wait(t);
      final rows = find.byType(ArtisanJobRow);
      expect(rows, findsNWidgets(10));
      for (final row in t.widgetList<ArtisanJobRow>(rows)) {
        final box = find.byWidget(row);
        expect(t.getRect(box).height, greaterThanOrEqualTo(88 - 0.5));
        expect(
          find.descendant(of: box, matching: find.byType(AppButton)),
          findsNothing,
        );
      }
    });

    testWidgets("a guest's join row sits after the third job", (t) async {
      final home = await _pump(t, height: 2400);
      await _wait(t);
      final rows = t
          .widgetList(find.byType(ArtisanJobRow))
          .map((row) => t.getRect(find.byWidget(row)).top)
          .toList();
      final join = _top(t, find.byType(ArtisanJoinRow));
      expect(join, greaterThan(rows[2]));
      expect(join, lessThan(rows[3]));
      await t.tap(find.byType(ArtisanJoinRow));
      await t.pump();
      expect(home.prompts, [AuthPrompt.joinAsArtisan]);
      // The header's link is for people who have a profile.
      await t.tap(find.text('Sign in'));
      await t.pump();
      expect(home.prompts.last, AuthPrompt.signIn);
    });

    testWidgets("a trade's demand line names it and its budgets", (t) async {
      await _pump(t, height: 2400);
      await _wait(t);
      await t.tap(find.widgetWithText(AppChip, 'AC repair'));
      await _wait(t);
      final demand = MockData.demand(categoryId: 'ac');
      expect(
        find.text('${demand.openThisWeek} AC repair jobs this week'),
        findsOneWidget,
      );
      expect(
        find.text('Most budgets ${ArtisanFormat.budget(
          demand.typicalBudgetMin,
          demand.typicalBudgetMax,
        )}'),
        findsOneWidget,
      );
      expect(
        find.text('See all ${demand.openThisWeek} AC repair jobs'),
        findsOneWidget,
      );
    });
  });

  group('Job sheet', () {
    testWidgets('opens from a row with the whole job', (t) async {
      final home = await _pump(t, height: 2400);
      await _wait(t);
      await t.tap(find.text('AC not cooling and leaking water'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(
        _inSheet(find.text('AC not cooling and leaking water')),
        findsOneWidget,
      );
      expect(_inSheet(find.text('AC repair')), findsOneWidget);
      expect(_inSheet(find.text('Urgent')), findsOneWidget);
      expect(_inSheet(find.textContaining('₦8,000–12,000')), findsOneWidget);
      expect(_inSheet(find.text('Garki Area 11')), findsOneWidget);
      expect(_inSheet(find.text('Be the first to quote')), findsOneWidget);
      expect(
        _inSheet(find.textContaining('Split unit in the sitting room')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'About the client: phone verified. 3 jobs posted on RijHub.',
        ),
        findsOneWidget,
      );
      // Guests learn that quoting starts with a free profile.
      expect(
        _inSheet(find.text(
          "Free to join. You'll add your phone number to send it.",
        )),
        findsOneWidget,
      );
      await t.tap(_inSheet(find.text('Send quote')));
      await t.pump();
      expect(home.prompts, [AuthPrompt.sendQuote]);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('Quoting', () {
    for (final (role, continues) in [
      (UserRole.artisan, true),
      (UserRole.client, false),
    ]) {
      testWidgets(
          'signing in as ${role.name} from "Send quote" '
          '${continues ? 'carries on' : 'stops'}', (t) async {
        final home = await _pump(
          t,
          screen: const HomeScreen(),
          height: 2400,
          presenter: (context, prompt) async {
            await context
                .read<SessionController>()
                .signIn(MockData.sampleUser(role));
            return true;
          },
        );
        await _wait(t);
        await t.tap(find.byType(ArtisanJobRow).first);
        await _wait(t, const Duration(milliseconds: 600));
        await t.tap(_inSheet(find.text('Send quote')));
        await _wait(t);
        expect(home.session.role, role);
        // The job sheet has closed either way.
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.text('Quoting is next in the redesign.'),
          continues ? findsOneWidget : findsNothing,
        );
      });
    }
  });
}
