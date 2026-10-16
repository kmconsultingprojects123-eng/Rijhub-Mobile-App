import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/routes.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/core/utils/formatters.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/onboarding/welcome_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mock, except that the server can't be reached to sign out.
class _OfflineAuth extends MockAuthRepository {
  int signOuts = 0;

  @override
  Future<void> signOut() async {
    signOuts++;
    throw const AuthException('No connection.');
  }
}

/// Records sign-in requests instead of showing the sheet.
class _FakeSheet {
  final prompts = <AuthPrompt>[];

  Future<bool> present(BuildContext context, AuthPrompt prompt) async {
    prompts.add(prompt);
    return false;
  }
}

/// The redesigned app on mock data. A fresh install unless [guestAs] or
/// [signedInAs] is given.
Future<(RijHubApp, SessionController, _FakeSheet)> _app({
  UserRole? guestAs,
  UserRole? signedInAs,
  String? location,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final deps = AppDependencies.mock();
  final session = SessionController(prefs: prefs, auth: deps.auth);
  if (guestAs != null) await session.continueAsGuest(guestAs);
  if (signedInAs != null) await session.signIn(MockData.sampleUser(signedInAs));
  final sheet = _FakeSheet();
  final app = RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: AuthFlowController(auth: deps.auth, session: session),
    authGate: AuthGate(sheet.present),
    initialLocation: location,
  );
  return (app, session, sheet);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// The welcome sheet first-time visitors see over the home.
Finder get _welcomeHeadline => find.byType(WelcomeSheet);

Finder _inWelcome(Finder finder) =>
    find.descendant(of: _welcomeHeadline, matching: finder);

void main() {
  group('NigerianPhone', () {
    test('accepts local, national and international forms', () {
      expect(NigerianPhone.normalize('0803 123 4567'), '8031234567');
      expect(NigerianPhone.normalize('+234 803 123 4567'), '8031234567');
      expect(NigerianPhone.normalize('8031234567'), '8031234567');
    });

    test('caps input at ten national digits', () {
      expect(NigerianPhone.normalize('080312345678999'), '8031234567');
    });

    test('validates mobile ranges', () {
      expect(NigerianPhone.isValid('8031234567'), isTrue);
      expect(NigerianPhone.isValid('9161234567'), isTrue);
      expect(NigerianPhone.isValid('6031234567'), isFalse);
      expect(NigerianPhone.isValid('803123456'), isFalse);
    });

    test('formats for display', () {
      expect(NigerianPhone.formatNational('8031234567'), '803 123 4567');
      expect(NigerianPhone.display('8031234567'), '+234 803 123 4567');
    });

    test('keeps the caret after the same digit when editing mid-number', () {
      final formatter = NigerianPhoneInputFormatter();
      // "803 123 4567" with a 9 typed after "803 1" (caret after the 9).
      const typed = TextEditingValue(
        text: '803 19234567',
        selection: TextSelection.collapsed(offset: 6),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, typed);
      expect(result.text, '803 192 3456');
      expect(result.selection.baseOffset, 6);
    });
  });

  group('Naira', () {
    test('formats whole naira with grouping', () {
      expect(Naira.format(8000), '₦8,000');
      expect(Naira.format(1250000), '₦1,250,000');
    });

    test('formats ranges and open budgets', () {
      expect(Naira.range(8000, 12000), '₦8,000 – ₦12,000');
      expect(Naira.range(25000, 25000), '₦25,000');
      expect(Naira.range(null, null), 'Open to quotes');
    });
  });

  group('Schedule', () {
    final now = DateTime(2026, 10, 16, 9);
    test('names nearby days', () {
      expect(
          Schedule.dayLabel(DateTime(2026, 10, 16, 14, 30), now: now), 'Today');
      expect(
          Schedule.dayLabel(DateTime(2026, 10, 17, 8), now: now), 'Tomorrow');
      expect(
          Schedule.dayLabel(DateTime(2026, 10, 15, 20), now: now), 'Yesterday');
      expect(
          Schedule.dayLabel(DateTime(2026, 10, 23, 9), now: now), 'Fri 23 Oct');
    });

    test('joins day and time', () {
      expect(
        Schedule.dayAndTime(DateTime(2026, 10, 16, 14, 30), now: now),
        'Today, 2:30 PM',
      );
    });
  });

  test('lower-cases labels mid-sentence but keeps acronyms', () {
    expect(TextCase.midSentence('Electrical'), 'electrical');
    expect(TextCase.midSentence('AC repair'), 'AC repair');
    expect(TextCase.midSentence('TV & decoder'), 'TV & decoder');
  });

  test('the area someone picks stays through signing in and out', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deps = AppDependencies.mock();
    final session = SessionController(prefs: prefs, auth: deps.auth);
    expect(session.area, isNull);
    await session.setArea('Gwarinpa');
    await session.signIn(MockData.sampleUser(UserRole.client));
    expect(session.area, 'Gwarinpa');
    await session.signOut();
    final restored = SessionController(prefs: prefs, auth: deps.auth)
      ..restore();
    expect(restored.area, 'Gwarinpa');
  });

  test('a saved value this version cannot read is dropped, not fatal',
      () async {
    SharedPreferences.setMockInitialValues({
      'session.guestRole': 'supervisor',
      'session.onboarded': 'yes',
      'session.area': 42,
      'session.user': '{"id": ',
    });
    final prefs = await SharedPreferences.getInstance();
    final session = SessionController(prefs: prefs, auth: MockAuthRepository())
      ..restore();
    expect(session.role, UserRole.client);
    expect(session.hasOnboarded, isFalse);
    expect(session.area, isNull);
    expect(session.isGuest, isTrue);
    expect(prefs.getKeys(), isEmpty);
  });

  test('signing out works offline, and asks the server only once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _OfflineAuth();
    final session = SessionController(prefs: prefs, auth: auth);
    await session.signIn(MockData.sampleUser(UserRole.client));
    await Future.wait([session.signOut(), session.signOut()]);
    expect(session.isGuest, isTrue);
    expect(auth.signOuts, 1);
    final restored = SessionController(prefs: prefs, auth: auth)..restore();
    expect(restored.isGuest, isTrue);
  });

  group('Mock accounts', () {
    late AppDependencies deps;
    late SessionController session;
    late AuthFlowController flow;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      deps = AppDependencies.mock();
      session = SessionController(prefs: prefs, auth: deps.auth);
      flow = AuthFlowController(auth: deps.auth, session: session);
    });

    /// Signs up 809 123 4567 through the sign-in flow, as a guest of [role]
    /// who has picked [area].
    Future<void> signUp(UserRole role, {String? area}) async {
      await session.continueAsGuest(role);
      if (area != null) await session.setArea(area);
      await flow.sendCode('8091234567');
      expect(await flow.verify('123456'), isFalse);
      await flow.createAccount(
        fullName: 'Ada Obi',
        tradeIds: role == UserRole.artisan ? ['plumbing'] : const [],
      );
    }

    test('a new client keeps all of Abuja and has no bookings', () async {
      await signUp(UserRole.client);
      expect(session.user!.homeArea, isNull);
      expect(session.area, isNull);
      expect(await deps.bookings.upcoming(as: UserRole.client), isEmpty);
    });

    test('a new artisan starts from zero, in the area they picked', () async {
      await signUp(UserRole.artisan, area: 'Gwarinpa');
      expect(session.user!.homeArea, 'Gwarinpa');
      // Their trades are on the account, for "My trades".
      expect(session.user!.tradeIds, ['plumbing']);
      final dashboard = await deps.artisanDashboard.dashboard();
      expect(dashboard.isAvailable, isFalse);
      expect(dashboard.availability, AvailabilityStatus.off);
      expect(dashboard.earningsThisWeek, 0);
      expect(dashboard.availableBalance, 0);
      // No wallet pill until there are earnings.
      expect(dashboard.earnedToDate, 0);
      expect(dashboard.reviewCount, 0);
      // Phone, trades and area are done; identity is next, and clients
      // can't book them until it is.
      expect(dashboard.setupDone, 3);
      final next = dashboard.setupSteps.firstWhere((s) => !s.done);
      expect(next.id, 'identity');
      expect(next.blocksBookings, isTrue);
      expect(await deps.bookings.upcoming(as: UserRole.artisan), isEmpty);
      expect(await deps.artisanDashboard.requests(), isEmpty);
      final jobs = await deps.jobs.openJobsNearby(area: 'Gwarinpa', limit: 3);
      expect(jobs.first.categoryId, 'plumbing');
    });

    test('only the sample client has hired anyone before', () async {
      expect(await deps.artisans.hiredBefore(), isEmpty, reason: 'a guest');
      await session.signIn(MockData.sampleUser(UserRole.client));
      final hired = await deps.artisans.hiredBefore();
      expect(hired.single.artisan.name, 'Yusuf Abdullahi');
      expect(hired.single.yourRating, 5);
      expect(hired.single.lastHiredOn.isBefore(DateTime.now()), isTrue);
      await session.signIn(MockData.sampleUser(UserRole.artisan));
      expect(await deps.artisans.hiredBefore(), isEmpty, reason: 'an artisan');
      await session.signOut();
      await signUp(UserRole.client);
      expect(await deps.artisans.hiredBefore(), isEmpty, reason: 'a new one');
    });

    test('the sample artisan has a request, and accepting it books it',
        () async {
      await session.signIn(MockData.sampleUser(UserRole.artisan));
      final request = (await deps.artisanDashboard.requests()).single;
      expect(request.clientName, 'Ngozi A.');
      expect(request.serviceName, 'Socket repair');
      // About 14 minutes to answer.
      final left = request.expiresAt.difference(DateTime.now());
      expect(left.inMinutes, inInclusiveRange(13, 14));

      final booking = await deps.artisanDashboard.respond(
        request.id,
        accept: true,
      );
      expect(booking!.serviceName, 'Socket repair');
      expect(booking.scheduledAt, request.window.start);
      final upcoming = await deps.bookings.upcoming(as: UserRole.artisan);
      expect(upcoming.map((b) => b.id), contains(booking.id));
      // Answered: it's gone, and answering again changes nothing.
      expect(await deps.artisanDashboard.requests(), isEmpty);
      expect(
        await deps.artisanDashboard.respond(request.id, accept: true),
        isNull,
      );
    });

    test('turning a request down books nothing', () async {
      await session.signIn(MockData.sampleUser(UserRole.artisan));
      final request = (await deps.artisanDashboard.requests()).single;
      expect(
        await deps.artisanDashboard.respond(request.id, accept: false),
        isNull,
      );
      expect(await deps.artisanDashboard.requests(), isEmpty);
      final upcoming = await deps.bookings.upcoming(as: UserRole.artisan);
      expect(
          upcoming.map((b) => b.serviceName), isNot(contains('Socket repair')));
    });

    test('availability is available, busy until a time, or off', () async {
      await session.signIn(MockData.sampleUser(UserRole.artisan));
      final dashboard = deps.artisanDashboard;
      expect((await dashboard.dashboard()).availability,
          AvailabilityStatus.available);

      final until = DateTime.now().add(const Duration(hours: 2));
      await dashboard.setAvailability(false, busyUntil: until);
      var now = await dashboard.dashboard();
      expect(now.availability, AvailabilityStatus.busy);
      expect(now.busyUntil, until);

      await dashboard.setAvailability(false);
      now = await dashboard.dashboard();
      expect(now.availability, AvailabilityStatus.off);
      expect(now.busyUntil, isNull);

      // A busy spell that has ended is available again, by itself.
      await dashboard.setAvailability(
        false,
        busyUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect((await dashboard.dashboard()).availability,
          AvailabilityStatus.available);
    });

    test('a number registered earlier signs straight back in', () async {
      await signUp(UserRole.client);
      await session.signOut();
      await flow.sendCode('8091234567');
      expect(await flow.verify('123456'), isTrue);
      expect(session.user!.firstName, 'Ada');
    });

    test('the sample accounts keep their bookings and earnings', () async {
      await session.signIn(MockData.sampleUser(UserRole.client));
      expect(await deps.bookings.upcoming(as: UserRole.client), isNotEmpty);
      await session.signIn(MockData.sampleUser(UserRole.artisan));
      expect((await deps.artisanDashboard.dashboard()).earningsThisWeek,
          MockData.dashboard.earningsThisWeek);
    });

    test('after a restart, data is for the account that was signed in',
        () async {
      await session.signIn(MockData.sampleUser(UserRole.client));
      // New mocks, as after a restart, which only the saved session tells
      // who is signed in.
      final relaunched = AppDependencies.mock();
      final restored = SessionController(
        prefs: await SharedPreferences.getInstance(),
        auth: relaunched.auth,
      );
      restored.restore();
      expect(
        await relaunched.bookings.upcoming(as: UserRole.client),
        isNotEmpty,
      );
    });
  });

  group('Mock data', () {
    test('lists the best rated first, filtered by trade and "free now"',
        () async {
      final artisans = AppDependencies.mock().artisans;
      final all = await artisans.topRatedNearby(area: 'Abuja');
      expect(all, hasLength(6));
      for (var i = 1; i < all.length; i++) {
        expect(all[i].rating, lessThanOrEqualTo(all[i - 1].rating));
      }
      final free = await artisans.topRatedNearby(area: 'Abuja', freeNow: true);
      expect(free, isNotEmpty);
      expect(free.every((a) => a.isAvailableToday), isTrue);
      final plumbers = await artisans.topRatedNearby(
        area: 'Abuja',
        categoryId: 'plumbing',
      );
      expect(plumbers, isNotEmpty);
      expect(plumbers.every((a) => a.categoryId == 'plumbing'), isTrue);
      // Someone who isn't free now says when they next are.
      for (final busy in all.where((a) => !a.isAvailableToday)) {
        expect(busy.nextFreeAt, isNotNull, reason: busy.name);
      }
      // The empty state can be shown: no generator technician is free.
      expect(
        await artisans.topRatedNearby(
          area: 'Abuja',
          categoryId: 'generator',
          freeNow: true,
        ),
        isEmpty,
      );
    });

    test('distances follow the area asked about', () async {
      final artisans = AppDependencies.mock().artisans;
      final near = await artisans.topRatedNearby(area: 'Wuse 2');
      final emeka = near.firstWhere((a) => a.name == 'Emeka Nwosu');
      expect(emeka.distanceKm, 1.2);
      final far = await artisans.topRatedNearby(area: 'Gwarinpa');
      expect(
        far.firstWhere((a) => a.name == 'Emeka Nwosu').distanceKm,
        greaterThan(emeka.distanceKm),
      );
    });

    test('counts open jobs for the city, an area and a trade', () async {
      final jobs = AppDependencies.mock().jobs;
      expect(await jobs.openJobsThisWeek(), 126);
      expect(await jobs.openJobsThisWeek(area: 'Abuja'), 126);
      expect(await jobs.openJobsThisWeek(area: 'Wuse 2'), 42);
      expect(await jobs.openJobsThisWeek(categoryId: 'ac'), 46);
      expect(await jobs.openJobsThisWeek(area: 'Wuse 2', categoryId: 'ac'), 18);
      final demand = await jobs.demand(categoryId: 'ac');
      expect(demand.openThisWeek, 46);
      expect(demand.postedToday, greaterThan(0));
      expect(demand.typicalBudgetMin, lessThan(demand.typicalBudgetMax!));
    });

    test('jobs come newest first, with a description and the client', () async {
      final jobs = await AppDependencies.mock()
          .jobs
          .openJobsNearby(area: 'Abuja', limit: 20);
      for (var i = 1; i < jobs.length; i++) {
        expect(jobs[i].postedAt.isAfter(jobs[i - 1].postedAt), isFalse);
      }
      final first = jobs.first;
      expect(first.description, isNotNull);
      expect(first.clientPhoneVerified, isTrue);
      expect(first.clientJobsPosted, greaterThan(0));
    });

    test('the price guide starts with the most asked about', () async {
      final guide = await AppDependencies.mock().catalog.priceGuide();
      expect(guide.length, inInclusiveRange(4, 6));
      expect(guide.first.categoryId, 'ac');
      expect(guide.first.minPrice, 8000);
      expect(guide.first.maxPrice, 12000);
      for (final item in guide) {
        expect(item.minPrice, lessThan(item.maxPrice), reason: item.problem);
      }
    });

    test('trades survive saving the account, and old saves have none', () {
      final emeka = MockData.sampleUser(UserRole.artisan);
      expect(emeka.tradeIds, ['ac', 'electrical']);
      final saved = jsonDecode(jsonEncode(emeka.toJson()));
      expect(
        AppUser.fromJson(saved as Map<String, Object?>).tradeIds,
        ['ac', 'electrical'],
      );
      final old = Map<String, Object?>.of(saved)..remove('tradeIds');
      expect(AppUser.fromJson(old).tradeIds, isEmpty);
    });
  });

  testWidgets('a section link is a 48pt target for touch and screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 100),
              // Short, so the test font's wide glyphs keep it on one line.
              SectionHeader(
                title: 'Jobs',
                actionLabel: 'See all',
                onAction: () => taps++,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ));
    final header = tester.getRect(find.byType(SectionHeader));
    final link = tester.getCenter(find.text('See all'));
    expect(header.height, lessThan(AppSize.minTapTarget));
    final node = tester.getSemantics(find.bySemanticsLabel('See all, Jobs'));
    expect(node.rect.height, AppSize.minTapTarget);
    await tester.tapAt(Offset(link.dx, header.top - 8));
    await tester.tapAt(Offset(link.dx, header.bottom + 8));
    expect(taps, 2);
    await tester.tapAt(Offset(link.dx, header.top - 20));
    expect(taps, 2);
    semantics.dispose();
  });

  group('AuthFlowController', () {
    late SessionController session;
    late AuthFlowController flow;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final deps = AppDependencies.mock();
      session = SessionController(prefs: prefs, auth: deps.auth);
      flow = AuthFlowController(auth: deps.auth, session: session);
    });

    test('starts on the phone step', () {
      flow.begin();
      expect(flow.resumeStep, AuthStep.phone);
    });

    test('resumes on the code step after a code was sent', () {
      flow.restoreChallenge(
        '8031234567',
        OtpChallenge(
          phone: '+2348031234567',
          channel: OtpChannel.sms,
          requestId: 't',
          resendAvailableAt: DateTime.now(),
        ),
      );
      flow.begin();
      expect(flow.resumeStep, AuthStep.code);
    });

    test('a code that arrives after starting over is ignored', () async {
      final sending = flow.sendCode('8031234567');
      flow.reset();
      await sending;
      expect(flow.phone, isNull);
      expect(flow.challenge, isNull);
      expect(flow.resumeStep, AuthStep.phone);
    });

    test('a check for a code that was replaced changes nothing', () async {
      await flow.sendCode('8091234567');
      final checking = flow.verify('123456');
      await flow.resend();
      expect(await checking, isNull);
      expect(flow.needsDetails, isFalse);
      expect(session.isSignedIn, isFalse);
    });

    test('new accounts take the role of the side being browsed', () async {
      await session.continueAsGuest(UserRole.artisan);
      expect(flow.role, UserRole.artisan);
    });
  });

  testWidgets('first launch shows the welcome over the guest home',
      (tester) async {
    final (app, _, _) = await _app(location: Routes.home);
    await tester.pumpWidget(app);
    await _settle(tester);
    expect(_welcomeHeadline, findsOneWidget);
    expect(_inWelcome(find.text('Explore as a guest')), findsOneWidget);
    expect(_inWelcome(find.text('Find work as an artisan')), findsOneWidget);
    // The real home is already loaded behind it.
    expect(find.text('What needs fixing?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one tap enters the app as a guest, with no sign-in',
      (tester) async {
    final (app, session, sheet) = await _app(location: Routes.welcome);
    await tester.pumpWidget(app);
    await _settle(tester);
    await tester.tap(_inWelcome(find.text('Explore as a guest')));
    await _settle(tester);
    expect(session.hasOnboarded, isTrue);
    expect(session.isGuest, isTrue);
    expect(session.role, UserRole.client);
    expect(_welcomeHeadline, findsNothing);
    // The client home, top-rated artisans first.
    expect(find.text('What needs fixing?'), findsOneWidget);
    expect(find.text('Top-rated in Abuja'), findsOneWidget);
    expect(sheet.prompts, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Find work as an artisan" enters as a guest artisan',
      (tester) async {
    final (app, session, sheet) = await _app(location: Routes.welcome);
    await tester.pumpWidget(app);
    await _settle(tester);
    expect(session.hasOnboarded, isFalse);
    await tester.tap(_inWelcome(find.text('Find work as an artisan')));
    await _settle(tester);
    expect(session.hasOnboarded, isTrue);
    expect(session.isGuest, isTrue);
    expect(session.role, UserRole.artisan);
    expect(find.text('Jobs near you'), findsOneWidget);
    expect(sheet.prompts, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('guests opening Bookings are invited to sign in', (tester) async {
    final (app, _, sheet) = await _app(
      guestAs: UserRole.client,
      location: Routes.bookings,
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    expect(find.text('Your bookings live here'), findsOneWidget);
    await tester.tap(find.text('Sign in or sign up'));
    await _settle(tester);
    expect(sheet.prompts.single, AuthPrompt.bookings);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signing in from welcome goes home once the sheet closes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deps = AppDependencies.mock();
    final session = SessionController(prefs: prefs, auth: deps.auth);
    final prompts = <AuthPrompt>[];
    await tester.pumpWidget(RijHubApp(
      dependencies: deps,
      session: session,
      authFlow: AuthFlowController(auth: deps.auth, session: session),
      authGate: AuthGate((context, prompt) async {
        prompts.add(prompt);
        await session.signIn(MockData.sampleUser(UserRole.client));
        return true;
      }),
      initialLocation: Routes.welcome,
    ));
    await _settle(tester);
    await tester.tap(_inWelcome(find.text('Sign in')));
    await _settle(tester);
    expect(prompts.single, AuthPrompt.signIn);
    expect(session.isSignedIn, isTrue);
    expect(_welcomeHeadline, findsNothing);
    expect(find.text('Home'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a QA launch that signs in over welcome lands on home',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deps = AppDependencies.mock();
    final session = SessionController(prefs: prefs, auth: deps.auth);
    await tester.pumpWidget(RijHubApp(
      dependencies: deps,
      session: session,
      authFlow: AuthFlowController(auth: deps.auth, session: session),
      authGate: AuthGate((context, prompt) async {
        await session.signIn(MockData.sampleUser(UserRole.client));
        return true;
      }),
      initialLocation: Routes.welcome,
      debugSignInPrompt: AuthPrompt.signIn,
    ));
    await _settle(tester);
    expect(session.isSignedIn, isTrue);
    expect(_welcomeHeadline, findsNothing);
    expect(find.text('Home'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("iOS's Reduce Motion turns animations off across the app",
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final (app, _, _) = await _app(
      guestAs: UserRole.client,
      location: Routes.account,
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    bool animationsOff() => MediaQuery.disableAnimationsOf(
        tester.element(find.text('Profile').first));
    expect(animationsOff(), isFalse);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(animationsOff(), isTrue);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    expect(animationsOff(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signed-in people skip the welcome screen', (tester) async {
    final (app, _, _) = await _app(
      signedInAs: UserRole.client,
      location: Routes.welcome,
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    expect(_welcomeHeadline, findsNothing);
    expect(find.text('Home'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the gate only asks guests', (tester) async {
    final (app, session, sheet) = await _app(
      signedInAs: UserRole.client,
      location: Routes.account,
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    final context = tester.element(find.text('Profile').first);
    final gate = AuthGate(sheet.present);
    expect(await gate.ensureSignedIn(context, AuthPrompt.postJob), isTrue);
    expect(sheet.prompts, isEmpty);
    // Signing out waits on the mock's real delay, which the test clock
    // doesn't advance.
    await tester.runAsync(session.signOut);
    await _settle(tester);
    expect(await gate.ensureSignedIn(context, AuthPrompt.postJob), isFalse);
    expect(sheet.prompts.single, AuthPrompt.postJob);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a second tap joins the sign-in already showing', (tester) async {
    final (app, _, _) = await _app(
      guestAs: UserRole.client,
      location: Routes.account,
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    final context = tester.element(find.text('Profile').first);
    final closed = Completer<bool>();
    var opened = 0;
    final gate = AuthGate((context, prompt) {
      opened++;
      return closed.future;
    });
    final first = gate.ensureSignedIn(context, AuthPrompt.postJob);
    final second = gate.ensureSignedIn(context, AuthPrompt.bookings);
    closed.complete(false);
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
