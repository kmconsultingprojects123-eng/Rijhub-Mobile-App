// End-to-end journeys through the redesigned app: the real router, session,
// sign-in flow and sign-in sheet (AuthGate(showAuthSheet)), on mock data.
//
// The mock repositories wait with Future.delayed, which completes when the
// test pumps fake time past it, so journeys pump rather than await them.
//
// The sample data is timed from the real clock (a booking 70-85 minutes
// away, a request that expires in 14 minutes), so nothing here depends on
// the time of day the tests run.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/auth/auth_sheet.dart';
import 'package:rijhub/features/onboarding/welcome_sheet.dart';
import 'package:rijhub/features/home/widgets/artisan_job_row.dart';
import 'package:rijhub/features/home/widgets/artisan_request_card.dart';
import 'package:rijhub/features/home/widgets/artisan_section_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One request for the client home's list: where, and with which filters.
typedef _ListRequest = ({String area, String? categoryId, bool freeNow});

/// Records what the client home asks for, and answers from the mock.
class _SpyArtisans implements ArtisanRepository {
  _SpyArtisans(this._inner);

  final ArtisanRepository _inner;
  final requests = <_ListRequest>[];

  /// The areas asked for, in order.
  List<String> get areas => [for (final r in requests) r.area];

  @override
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  }) {
    requests.add((area: area, categoryId: categoryId, freeNow: freeNow));
    return _inner.topRatedNearby(
      area: area,
      categoryId: categoryId,
      freeNow: freeNow,
      limit: limit,
    );
  }

  @override
  Future<List<HiredArtisan>> hiredBefore() => _inner.hiredBefore();
}

/// The mock, except that signing out fails, as it would offline.
class _OfflineSignOut extends MockAuthRepository {
  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    throw const AuthException('No connection.');
  }
}

/// One running copy of the app and the state behind it.
class _Run {
  _Run(this.prefs, this.session, this.flow, this.artisans, this.deps);

  final SharedPreferences prefs;
  final SessionController session;
  final AuthFlowController flow;
  final _SpyArtisans artisans;
  final AppDependencies deps;
}

/// Starts the app as `main.dart` does: restores the session from [prefs]
/// (a fresh install unless given) and opens on the splash screen.
///
/// [height] makes the phone taller, so a whole home screen is built at once.
Future<_Run> _launch(
  WidgetTester t, {
  SharedPreferences? prefs,
  AuthRepository? auth,
  double height = 844,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(390 * 3, height * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);

  if (prefs == null) {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }
  final mock = AppDependencies.mock();
  final artisans = _SpyArtisans(mock.artisans);
  final deps = AppDependencies(
    auth: auth ?? mock.auth,
    catalog: mock.catalog,
    artisans: artisans,
    jobs: mock.jobs,
    bookings: mock.bookings,
    artisanDashboard: mock.artisanDashboard,
  );
  final session = SessionController(prefs: prefs, auth: deps.auth)..restore();
  final flow = AuthFlowController(auth: deps.auth, session: session);
  // A new widget tree, so a relaunch builds a new router for its session.
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: flow,
    authGate: AuthGate(showAuthSheet),
  ));
  // Past the splash's brand moment, the cross-fade and the first loads.
  await _wait(t, const Duration(milliseconds: 2200));
  return _Run(prefs, session, flow, artisans, deps);
}

/// A fresh install that has already been through welcome as [role], or
/// signed in as that role's sample user.
Future<SharedPreferences> _installed(UserRole role,
    {bool signedIn = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = SessionController(prefs: prefs, auth: MockAuthRepository());
  if (signedIn) {
    await session.signIn(MockData.sampleUser(role));
  } else {
    await session.continueAsGuest(role);
  }
  return prefs;
}

/// Pumps [total] of fake time in short frames, so timers, mock latencies
/// and animations all run.
Future<void> _wait(
  WidgetTester t, [
  Duration total = const Duration(milliseconds: 1500),
]) async {
  const frame = Duration(milliseconds: 50);
  for (var waited = Duration.zero; waited < total; waited += frame) {
    await t.pump(frame);
  }
}

/// Waits for [future], pumping fake time so the mock's latency runs out.
Future<T> _await<T>(WidgetTester t, Future<T> future) async {
  await _wait(t, const Duration(milliseconds: 800));
  return future;
}

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _wait(t, const Duration(milliseconds: 500));
}

/// The open sheets: the sign-in sheet, the area picker, the job sheet or
/// the availability sheet.
Finder get _sheet => find.byType(BottomSheet);

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

/// The sheet's text field: the phone number, the code, the name or the
/// area search.
Finder get _field => _inSheet(find.byType(TextField));

String get _fieldText =>
    (_field.evaluate().single.widget as TextField).controller!.text;

/// The welcome sheet first-time visitors see over the home.
Finder get _welcome => find.byType(WelcomeSheet);

Finder _inWelcome(Finder finder) =>
    find.descendant(of: _welcome, matching: finder);

/// The client home: its search asks what needs fixing.
Finder get _clientHome => find.text('What needs fixing?');

/// The artisan home before signing in.
Finder get _artisanGuestHome => find.text('Jobs near you');

/// The sample client's booking card, by its start code. Only she has it.
Finder get _herBooking => find.textContaining('Code 4829');

/// The bell signed-in people have in place of "Sign in".
Finder get _bell => find.bySemanticsLabel('Notifications');

/// The client header's "Sign in", which guests have.
Finder get _clientSignIn => find.widgetWithText(AppButton, 'Sign in');

/// The signed-in artisan's availability pill, saying [state].
Finder _availability(String state) =>
    find.bySemanticsLabel(RegExp('^Availability\\. $state'));

/// The sample artisan's earnings this week, on the wallet pill.
Finder get _hisEarnings => find.text('₦86,500');

/// The ID check that comes before a new artisan can be booked.
Finder get _idBanner => find.text('Verify your ID to start getting booked');

Finder _pill(String place) => find.bySemanticsLabel('Area: $place. Change');

/// The post-a-job row under the client home's list.
const _postJobRow = 'Not sure who to pick?';

const _wrongCode = "That code isn't right. Check the message and try again.";

/// Scrolls [finder] into view and taps it.
Future<void> _tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder.first);
  await t.pump();
  await t.tap(finder.first);
  await t.pump();
}

Future<void> _tapText(WidgetTester t, String text) => _tap(t, find.text(text));

/// Leaves the welcome sheet as a guest of [role]: one button each.
Future<void> _enter(WidgetTester t, UserRole role) async {
  await t.tap(_inWelcome(find.text(
    role == UserRole.artisan ? 'Find work as an artisan' : 'Explore as a guest',
  )));
  await _wait(t);
}

/// The welcome sheet's "Sign in", for returning people.
Future<void> _signInFromWelcome(WidgetTester t) async {
  await t.tap(_inWelcome(find.text('Sign in')));
  await _wait(t, const Duration(milliseconds: 500));
}

/// Taps an action that needs an account and waits for the sheet to rise.
Future<void> _ask(WidgetTester t, String action) async {
  await _tapText(t, action);
  await _wait(t, const Duration(milliseconds: 500));
}

/// The client home's way to post a job: the row under the list.
Future<void> _postJob(WidgetTester t) => _ask(t, _postJobRow);

/// Opens the job called [title] from the artisan home's list.
Future<void> _openJob(WidgetTester t, String title) async {
  await _tapText(t, title);
  await _wait(t, const Duration(milliseconds: 500));
}

/// Opens the job called [title] and taps its "Send quote".
Future<void> _quoteOn(WidgetTester t, String title) async {
  await _openJob(t, title);
  await t.tap(_inSheet(find.text('Send quote')));
  await _wait(t, const Duration(milliseconds: 500));
}

/// Enters [phone] on the phone step and sends the code.
Future<void> _sendCode(WidgetTester t, String phone) async {
  await t.enterText(_field, phone);
  await t.pump();
  await t.tap(_inSheet(find.text('Send code')));
  // The mock takes 700 ms, then the code step slides in.
  await _wait(t, const Duration(milliseconds: 1200));
}

/// Types a full code, which checks it at once.
Future<void> _enterCode(WidgetTester t, String code) async {
  await t.enterText(_field, code);
  await t.pump();
  // The mock takes 800 ms to check it, then the next step slides in.
  await _wait(t, const Duration(milliseconds: 1300));
}

/// Waits through "You're all set" until the sheet has gone.
Future<void> _waitForSheetToClose(WidgetTester t) =>
    _wait(t, const Duration(milliseconds: 1400));

Future<void> _closeSheet(WidgetTester t) async {
  await t.tap(_inSheet(find.bySemanticsLabel('Close')).last);
  await _wait(t, const Duration(milliseconds: 600));
}

Future<void> _openTab(WidgetTester t, IconData icon) async {
  await t.tap(find.byIcon(icon));
  await _wait(t, const Duration(milliseconds: 600));
}

/// Signs in on the sheet that is open, as an existing account.
Future<void> _signInOnSheet(WidgetTester t, String phone) async {
  await _sendCode(t, phone);
  await _enterCode(t, '482915');
  await _waitForSheetToClose(t);
}

/// Creates a client account for a new number on the sheet that is open.
Future<void> _signUpClient(WidgetTester t, String name) async {
  await _sendCode(t, '8091234567');
  await _enterCode(t, '123456');
  await t.enterText(_field, name);
  await t.pump();
  await t.tap(_inSheet(find.text('Create account')));
  await _wait(t, const Duration(milliseconds: 900));
  await _waitForSheetToClose(t);
}

/// Creates an artisan profile for a new number on the sheet that is open.
Future<void> _signUpArtisan(
  WidgetTester t,
  String name,
  List<String> trades,
) async {
  await _sendCode(t, '8091234567');
  await _enterCode(t, '123456');
  // The trades load.
  await _wait(t, const Duration(milliseconds: 400));
  await t.enterText(_field, name);
  await t.pump();
  for (final trade in trades) {
    await _tap(t, _tradeChip(trade));
  }
  await _tap(t, _inSheet(find.text('Create profile')));
  await _wait(t, const Duration(milliseconds: 900));
  await _waitForSheetToClose(t);
}

AppButton _button(WidgetTester t, String label) =>
    t.widget<AppButton>(_inSheet(find.widgetWithText(AppButton, label)));

/// A trade chip on the profile step. Chips only: a job sheet underneath
/// names its trade too.
Finder _tradeChip(String label) =>
    _inSheet(find.widgetWithText(AppChip, label));

AppChip _chip(WidgetTester t, String label) =>
    t.widget<AppChip>(_tradeChip(label));

/// A filter chip on the home, outside any sheet, even one scrolled out of
/// sight along its row.
AppChip _filter(WidgetTester t, String label) => t.widget<AppChip>(
      find.widgetWithText(AppChip, label, skipOffstage: false),
    );

/// The client home's rows, by the artisan's name, top to bottom.
List<String> _listedArtisans(WidgetTester t) {
  final names = {
    for (final artisan in MockData.artisans) artisan.name,
  };
  final shown = [
    for (final element in find.byType(Text).evaluate())
      if ((element.widget as Text).data case final name?
          when names.contains(name))
        (
          name,
          (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
        ),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (name, _) in shown) name];
}

/// Lays text out in Inter, as on a device. The test font's wider glyphs
/// would overflow rows that fit in the real one.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  group('Clients', () {
    testWidgets('explore as a guest, then sign in to post a job', (t) async {
      final run = await _launch(t);
      expect(_welcome, findsOneWidget);

      await _enter(t, UserRole.client);
      expect(_welcome, findsNothing);
      expect(run.session.isGuest, isTrue);
      expect(run.session.role, UserRole.client);
      expect(_sheet, findsNothing, reason: 'nothing is asked for up front');
      expect(_clientHome, findsOneWidget);
      expect(_clientSignIn, findsOneWidget);
      // The first thing a guest sees is who can fix things.
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(find.text('Emeka Nwosu'), findsOneWidget);

      await _postJob(t);
      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.text('Post your job')), findsOneWidget);

      await _sendCode(t, '8031234567');
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);
      expect(
        _inSheet(find.textContaining('803 123 4567')),
        findsOneWidget,
      );

      await _enterCode(t, '482915');
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      expect(_inSheet(find.text('Welcome back, Chidinma.')), findsOneWidget);
      await _waitForSheetToClose(t);

      expect(_sheet, findsNothing);
      expect(run.session.isSignedIn, isTrue);
      expect(run.session.user!.firstName, 'Chidinma');
      // Home is hers now: her booking, and the bell where Sign in was.
      expect(_herBooking, findsOneWidget);
      expect(_clientSignIn, findsNothing);
      expect(_bell, findsOneWidget);
      // The action that asked for the account carries on.
      expect(
        find.text('Posting a job is next in the redesign.'),
        findsOneWidget,
      );
      await _dispose(t);
    });

    testWidgets('a new number adds a name, then is signed in', (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');

      expect(_inSheet(find.text("What's your name?")), findsOneWidget);
      expect(run.session.isGuest, isTrue);
      // Two letters turn Create account on.
      expect(_button(t, 'Create account').onPressed, isNull);
      await t.enterText(_field, 'Ada Obi');
      await t.pump();
      expect(_button(t, 'Create account').onPressed, isNotNull);

      await t.tap(_inSheet(find.text('Create account')));
      await _wait(t, const Duration(milliseconds: 900));
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      expect(_inSheet(find.text('Welcome, Ada.')), findsOneWidget);
      await _waitForSheetToClose(t);

      expect(_sheet, findsNothing);
      expect(run.session.user!.firstName, 'Ada');
      expect(run.session.user!.lastName, 'Obi');
      expect(run.session.user!.role, UserRole.client);
      // The home has switched to her account, which has nothing booked.
      expect(_bell, findsOneWidget);
      expect(_clientSignIn, findsNothing);
      expect(_herBooking, findsNothing);
      expect(
        find.text('Posting a job is next in the redesign.'),
        findsOneWidget,
      );
      await _dispose(t);
    });

    testWidgets('picking an area updates the pill and reloads artisans',
        (t) async {
      final run = await _launch(t, height: 1800);
      await _enter(t, UserRole.client);
      expect(run.artisans.areas, ['Abuja']);
      expect(_pill('Abuja'), findsOneWidget);
      expect(find.text('Top-rated in Abuja'), findsOneWidget);

      await t.tap(_pill('Abuja'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Choose your area')), findsOneWidget);
      await t.enterText(_field, 'gwar');
      await t.pump();
      await t.tap(_inSheet(find.text('Gwarinpa')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      expect(run.session.area, 'Gwarinpa');
      expect(run.artisans.areas, ['Abuja', 'Gwarinpa']);
      // The old list never shows under the new name.
      expect(find.text('Emeka Nwosu'), findsNothing);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_sheet, findsNothing);
      expect(_pill('Gwarinpa'), findsOneWidget);
      expect(find.text('Top-rated near you'), findsOneWidget);
      expect(find.text('Emeka Nwosu'), findsOneWidget);

      // The picker reopens with the choice ticked.
      await t.tap(_pill('Gwarinpa'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(
        find.bySemanticsLabel('Gwarinpa'),
        findsOneWidget,
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Gwarinpa')),
        matchesSemantics(
          label: 'Gwarinpa',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      await _dispose(t);
    });
  });

  group('Client home', () {
    testWidgets('"Free now" and a trade filter the list in place', (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.client),
        height: 1800,
      );
      expect(_listedArtisans(t), [
        'Emeka Nwosu',
        'Ibrahim Musa',
        'Chinedu Eze',
        'Yusuf Abdullahi',
        'Kunle Adebayo',
      ]);
      // Chinedu is next free tomorrow.
      expect(find.textContaining('Free tomorrow'), findsOneWidget);

      await _tap(t, find.widgetWithText(AppChip, 'Free now'));
      expect(_filter(t, 'Free now').selected, isTrue);
      await _wait(t);
      expect(run.artisans.requests.last,
          (area: 'Abuja', categoryId: null, freeNow: true));
      // Still Home, still the same section: only the rows changed.
      expect(_clientHome, findsOneWidget);
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(find.text('Chinedu Eze'), findsNothing);
      expect(find.textContaining('Free tomorrow'), findsNothing);
      final free = _listedArtisans(t);
      expect(free, hasLength(5));
      for (final name in free) {
        final artisan = MockData.artisans.firstWhere((a) => a.name == name);
        expect(artisan.isAvailableToday, isTrue, reason: name);
      }
      expect(find.textContaining('● Free now'), findsNWidgets(5));

      // A trade narrows it further; "Free now" stays on.
      await _tap(t, find.widgetWithText(AppChip, 'Plumbing'));
      await _wait(t);
      expect(run.artisans.requests.last,
          (area: 'Abuja', categoryId: 'plumbing', freeNow: true));
      expect(_filter(t, 'Plumbing').selected, isTrue);
      expect(_filter(t, 'All').selected, isFalse);
      expect(_listedArtisans(t), ['Yusuf Abdullahi']);

      // "Free now" off brings back the plumber who is busy today.
      await _tap(t, find.widgetWithText(AppChip, 'Free now'));
      await _wait(t);
      expect(_listedArtisans(t), ['Yusuf Abdullahi', 'Daniel Bassey']);

      // "All" is every trade again.
      await _tap(t, find.widgetWithText(AppChip, 'All'));
      await _wait(t);
      expect(run.artisans.requests.last,
          (area: 'Abuja', categoryId: null, freeNow: false));
      expect(_listedArtisans(t).first, 'Emeka Nwosu');
      expect(_listedArtisans(t), hasLength(5));
      expect(find.text('Coming in the redesign'), findsNothing);
      await _dispose(t);
    });

    testWidgets('a filter nobody fits says so, with the way out', (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.client),
        height: 1800,
      );
      await _tap(t, find.widgetWithText(AppChip, 'Free now'));
      await _tap(t, find.widgetWithText(AppChip, 'Generator'));
      await _wait(t);
      expect(_listedArtisans(t), isEmpty);
      expect(
        find.text('No generator technicians free right now'),
        findsOneWidget,
      );
      // "See all" has nothing more to show.
      expect(find.text('See all'), findsNothing);
      // Posting the job is still right below.
      expect(find.text(_postJobRow), findsOneWidget);

      await _tapText(t, 'Turn off Free now');
      await _wait(t);
      expect(_filter(t, 'Free now').selected, isFalse);
      expect(_filter(t, 'Generator').selected, isTrue);
      expect(_listedArtisans(t), ['Tunde Bakare']);
      await _dispose(t);
    });

    testWidgets('a past hire leads the list with "Book again", for her only',
        (t) async {
      // A guest has no past hires.
      await _launch(
        t,
        prefs: await _installed(UserRole.client),
        height: 1800,
      );
      expect(find.text('Emeka Nwosu'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Book .* again\$')), findsNothing);
      expect(find.textContaining('You hired'), findsNothing);

      // The sample client had Yusuf fix a leak before.
      await _launch(
        t,
        prefs: await _installed(UserRole.client, signedIn: true),
        height: 1800,
      );
      expect(_listedArtisans(t).first, 'Yusuf Abdullahi');
      // He leads the list once, not again further down.
      expect(find.text('Yusuf Abdullahi'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Book Yusuf Abdullahi again'), findsOneWidget);
      expect(find.textContaining('You hired Yusuf'), findsOneWidget);
      expect(find.textContaining('you rated 5'), findsOneWidget);
      // Emeka, her upcoming booking, is listed once, as usual, with his price.
      expect(find.text('Emeka Nwosu'), findsWidgets);
      expect(find.bySemanticsLabel('Book Emeka Nwosu again'), findsNothing);

      await t.tap(find.bySemanticsLabel('Book Yusuf Abdullahi again'));
      await _wait(t, const Duration(milliseconds: 400));
      expect(
        find.text('Booking Yusuf again is next in the redesign.'),
        findsOneWidget,
      );

      // Only while he fits the filters.
      await _tap(t, find.widgetWithText(AppChip, 'Plumbing'));
      await _wait(t);
      expect(find.bySemanticsLabel('Book Emeka Nwosu again'), findsNothing);
      expect(find.text('Emeka Nwosu'), findsNothing);
      await _dispose(t);
    });

    testWidgets('a price row picks its trade and goes back up to the list',
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      await _tapText(t, 'Sink or toilet leak');
      await _wait(t);
      expect(_filter(t, 'Plumbing').selected, isTrue);
      expect(run.artisans.requests.last.categoryId, 'plumbing');
      // Back at the top, where the plumbers are.
      expect(
        t.getRect(find.text('Top-rated in Abuja')).top,
        lessThan(844 / 2),
      );
      expect(find.text('Yusuf Abdullahi'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('the booking card opens Bookings, and chat says it is next',
        (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.client, signedIn: true),
      );
      await t.tap(find.bySemanticsLabel('Message Emeka'));
      await _wait(t, const Duration(milliseconds: 400));
      expect(find.text('Chat is next in the redesign.'), findsOneWidget);

      await t.tap(_herBooking);
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Coming in the redesign'), findsOneWidget);
      expect(find.text('Track every booking, from quote to payment.'),
          findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a guest who fixes things can go to the artisan side',
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.client),
        height: 1800,
      );
      await _tapText(t, 'Do you fix things? Find work on RijHub');
      await _wait(t);
      expect(run.session.role, UserRole.artisan);
      expect(run.session.isGuest, isTrue);
      expect(_artisanGuestHome, findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      // Signed-in clients don't see it.
      await _launch(
        t,
        prefs: await _installed(UserRole.client, signedIn: true),
        height: 1800,
      );
      expect(find.text('Do you fix things? Find work on RijHub'), findsNothing);
      await _dispose(t);
    });
  });

  group('Artisans', () {
    testWidgets(
        'a guest quotes on a job, creates a profile with up to 3 trades and '
        'lands on the dashboard', (t) async {
      final run = await _launch(t, height: 1800);
      await _enter(t, UserRole.artisan);
      expect(run.session.role, UserRole.artisan);
      expect(_artisanGuestHome, findsOneWidget);
      expect(_sheet, findsNothing);

      await _quoteOn(t, 'Socket sparking in the kitchen');
      expect(_inSheet(find.text('Send your quote')), findsOneWidget);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      // The trades load.
      await _wait(t, const Duration(milliseconds: 400));
      expect(_inSheet(find.text('Set up your profile')), findsOneWidget);

      await t.enterText(_field, 'Tunde Bakare');
      await t.pump();
      expect(
        _button(t, 'Create profile').onPressed,
        isNull,
        reason: 'an artisan picks at least one trade',
      );
      for (final trade in ['AC repair', 'Generator', 'Solar']) {
        await _tap(t, _tradeChip(trade));
      }
      expect(_chip(t, 'Solar').selected, isTrue);
      await _tap(t, _tradeChip('Plumbing'));
      expect(_chip(t, 'Plumbing').selected, isFalse);
      expect(
        _inSheet(find.text('You can pick up to 3 for now.')),
        findsOneWidget,
      );
      // Taking one off makes room again.
      await _tap(t, _tradeChip('Solar'));
      await _tap(t, _tradeChip('Plumbing'));
      expect(_chip(t, 'Plumbing').selected, isTrue);
      expect(_chip(t, 'Solar').selected, isFalse);

      await _tap(t, _inSheet(find.text('Create profile')));
      await _wait(t, const Duration(milliseconds: 900));
      expect(_inSheet(find.text('Welcome, Tunde.')), findsOneWidget);
      await _waitForSheetToClose(t);

      // The sign-in sheet and the job sheet under it have both closed.
      expect(_sheet, findsNothing);
      expect(run.session.user!.role, UserRole.artisan);
      expect(run.session.user!.tradeIds, ['ac', 'generator', 'plumbing']);
      // The guest view gave way to the dashboard by itself: a new profile
      // is off until the ID check is done.
      expect(_artisanGuestHome, findsNothing);
      expect(_availability('Off'), findsOneWidget);
      expect(_idBanner, findsOneWidget);
      expect(find.text('Quoting is next in the redesign.'), findsOneWidget);
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('New jobs for you'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a guest joins free from the row among the jobs', (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan),
        height: 1800,
      );
      await _ask(t, 'Join free');
      expect(_inSheet(find.text('Create your free profile')), findsOneWidget);
      await _signUpArtisan(t, 'Tunde Bakare', ['Generator']);
      expect(_sheet, findsNothing);
      expect(run.session.user!.role, UserRole.artisan);
      expect(run.session.user!.tradeIds, ['generator']);
      expect(_artisanGuestHome, findsNothing);
      expect(_availability('Off'), findsOneWidget);
      // Joining isn't quoting, so nothing is said about quotes.
      expect(find.text('Quoting is next in the redesign.'), findsNothing);
      await _dispose(t);
    });

    testWidgets('an existing artisan signs in from the guest header',
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.artisan));
      expect(_artisanGuestHome, findsOneWidget);
      await _ask(t, 'Sign in');
      expect(_inSheet(find.text('Welcome back')), findsOneWidget);
      await _signInOnSheet(t, '8059876543');
      expect(run.session.user!.firstName, 'Emeka');
      expect(_artisanGuestHome, findsNothing);
      expect(_availability('Available'), findsOneWidget);
      expect(_hisEarnings, findsOneWidget);
      await _dispose(t);
    });
  });

  group('Artisan home', () {
    testWidgets('the availability pill opens a sheet that changes it',
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
      );
      expect(_availability('Available'), findsOneWidget);

      await t.tap(_availability('Available'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Your availability')), findsOneWidget);
      // How much work there is today, in his main trade and area.
      final today =
          MockData.demand(area: 'Wuse 2', categoryId: 'ac').postedToday;
      expect(
        _inSheet(find.text('$today AC repair jobs posted today near Wuse 2')),
        findsOneWidget,
      );

      // Off.
      await t.tap(_inSheet(find.text('Off')));
      await _wait(t, const Duration(milliseconds: 800));
      expect(_sheet, findsNothing);
      expect(_availability('Off'), findsOneWidget);
      var saved = await _await(t, run.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.off);

      // Busy for an hour.
      await t.tap(_availability('Off'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.tap(_inSheet(find.text('Busy until…')));
      await t.pump();
      final hours = _inSheet(find.byType(AppChip));
      expect(hours, findsNWidgets(3));
      final firstLabel = t.widget<AppChip>(hours.first).label;
      await t.tap(hours.first);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_sheet, findsNothing);
      expect(find.text('Busy till $firstLabel'), findsOneWidget);
      saved = await _await(t, run.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.busy);
      expect(saved.busyUntil, isNotNull);

      // Available again.
      await t.tap(find.text('Busy till $firstLabel'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.tap(_inSheet(find.text('Available now')));
      await _wait(t, const Duration(milliseconds: 800));
      expect(_availability('Available'), findsOneWidget);
      saved = await _await(t, run.deps.artisanDashboard.dashboard());
      expect(saved.availability, AvailabilityStatus.available);
      await _dispose(t);
    });

    testWidgets("accepting a request books it and takes it off Home",
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
        height: 1800,
      );
      expect(find.byType(ArtisanRequestCard), findsOneWidget);
      expect(find.text('Ngozi A. wants to book you'), findsOneWidget);
      expect(find.text('REQUESTS FOR YOU · 1'), findsOneWidget);

      await t.tap(find.bySemanticsLabel("Accept Ngozi A.'s request"));
      await _wait(t);
      expect(find.byType(ArtisanRequestCard), findsNothing);
      expect(find.text('REQUESTS FOR YOU · 1'), findsNothing);
      expect(find.text("Booked. It's in your schedule."), findsOneWidget);
      final upcoming = await _await(
        t,
        run.deps.bookings.upcoming(as: UserRole.artisan),
      );
      expect(upcoming.map((b) => b.serviceName), contains('Socket repair'));
      // It's answered, so it doesn't come back.
      final requests = await _await(t, run.deps.artisanDashboard.requests());
      expect(requests, isEmpty);
      await _dispose(t);
    });

    testWidgets('"Not now" turns a request down quietly', (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
        height: 1800,
      );
      await t.tap(find.bySemanticsLabel("Not now: turn down Ngozi A.'s "
          'request'));
      await _wait(t);
      expect(find.byType(ArtisanRequestCard), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      final upcoming = await _await(
        t,
        run.deps.bookings.upcoming(as: UserRole.artisan),
      );
      expect(
        upcoming.map((b) => b.serviceName),
        isNot(contains('Socket repair')),
      );
      await _dispose(t);
    });

    testWidgets('a job opens in a sheet, and quoting asks a guest to join',
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan),
        height: 1800,
      );
      await _openJob(t, 'AC not cooling and leaking water');
      // The whole job, to decide on.
      expect(
        _inSheet(find.text('AC not cooling and leaking water')),
        findsOneWidget,
      );
      expect(_inSheet(find.textContaining('₦8,000–12,000')), findsOneWidget);
      expect(_inSheet(find.text('AC repair')), findsOneWidget);
      expect(_inSheet(find.textContaining('Split unit in the sitting room')),
          findsOneWidget);
      expect(
        _inSheet(find.textContaining('3 jobs posted on RijHub')),
        findsOneWidget,
      );
      expect(_inSheet(find.textContaining('Phone verified')), findsOneWidget);

      await t.tap(_inSheet(find.text('Send quote')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Send your quote')), findsOneWidget);
      expect(run.session.isGuest, isTrue);

      // Closing the sign-in sheet leaves the job open.
      await _closeSheet(t);
      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.text('Send quote')), findsOneWidget);
      await _closeSheet(t);
      expect(_sheet, findsNothing);
      expect(_artisanGuestHome, findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a signed-in artisan quotes from the job sheet directly',
        (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
        height: 1800,
      );
      await _quoteOn(t, 'Socket sparking in the kitchen');
      expect(_inSheet(find.text('Send your quote')), findsNothing);
      expect(_sheet, findsNothing);
      expect(find.text('Quoting is next in the redesign.'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets("new jobs start with the artisan's trades", (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
        height: 1800,
      );
      // His home area, from his account.
      expect(run.session.area, 'Wuse 2');
      int thisWeek([String? trade]) =>
          MockData.demand(area: 'Wuse 2', categoryId: trade).openThisWeek;

      expect(_filter(t, 'My trades').selected, isTrue);
      final trades = run.session.user!.tradeIds.toSet();
      expect(trades, {'ac', 'electrical'});
      List<String> shownTrades() => [
            for (final row in t.widgetList<ArtisanJobRow>(
              find.byType(ArtisanJobRow),
            ))
              row.job.categoryId,
          ];
      expect(shownTrades(), isNotEmpty);
      expect(shownTrades().every(trades.contains), isTrue);
      expect(find.text('Fix a leaking kitchen tap'), findsNothing);
      expect(
        find.text('See all ${thisWeek('ac') + thisWeek('electrical')} jobs'),
        findsOneWidget,
      );

      // Every trade: his still come first, and "See all" counts them all.
      await _tap(t, find.widgetWithText(AppChip, 'All'));
      await _wait(t);
      expect(_filter(t, 'My trades').selected, isFalse);
      expect(find.text('See all ${thisWeek()} jobs'), findsOneWidget);

      await _tap(t, find.widgetWithText(AppChip, 'Plumbing'));
      await _wait(t);
      expect(shownTrades(), isNotEmpty);
      expect(shownTrades().every((id) => id == 'plumbing'), isTrue);
      expect(find.text('Fix a leaking kitchen tap'), findsOneWidget);
      expect(
        find.text('See all ${thisWeek('plumbing')} plumbing jobs'),
        findsOneWidget,
      );
      await _dispose(t);
    });
  });

  group('Profile tab', () {
    testWidgets('signing out keeps a client in the app as a guest client',
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.client, signedIn: true),
      );
      expect(_herBooking, findsOneWidget);
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      expect(find.text('Chidinma Okafor'), findsOneWidget);

      await _tapText(t, 'Sign out');
      await _wait(t, const Duration(milliseconds: 400));
      expect(run.session.isGuest, isTrue);
      expect(run.session.role, UserRole.client);
      expect(run.session.hasOnboarded, isTrue);
      expect(_welcome, findsNothing);
      expect(find.text('Join RijHub'), findsOneWidget);

      await _openTab(t, IconsaxPlusLinear.home_2);
      expect(_clientHome, findsOneWidget);
      expect(_herBooking, findsNothing);
      expect(find.bySemanticsLabel('Book Emeka Nwosu again'), findsNothing);
      expect(_clientSignIn, findsOneWidget);
      await _dispose(t);
    });

    testWidgets('signing out keeps an artisan on the artisan side', (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
      );
      expect(_hisEarnings, findsOneWidget);
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Sign out');
      await _wait(t, const Duration(milliseconds: 400));

      expect(run.session.isGuest, isTrue);
      expect(run.session.role, UserRole.artisan);
      expect(find.text('Start getting jobs'), findsOneWidget);
      // Artisan tab labels stay.
      expect(find.text('Jobs'), findsOneWidget);
      await _openTab(t, IconsaxPlusLinear.home_2);
      expect(_artisanGuestHome, findsOneWidget);
      expect(_hisEarnings, findsNothing);
      await _dispose(t);
    });

    testWidgets('a guest switches between hiring and finding work', (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      expect(find.text('Join RijHub'), findsOneWidget);

      await _tapText(t, 'Find work on RijHub');
      await _wait(t, const Duration(milliseconds: 400));
      expect(run.session.role, UserRole.artisan);
      expect(run.session.isGuest, isTrue);
      expect(find.text('Start getting jobs'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      await _openTab(t, IconsaxPlusLinear.home_2);
      expect(_artisanGuestHome, findsOneWidget);

      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Hire an artisan');
      await _wait(t, const Duration(milliseconds: 400));
      expect(run.session.role, UserRole.client);
      expect(find.text('Join RijHub'), findsOneWidget);
      await _openTab(t, IconsaxPlusLinear.home_2);
      expect(_clientHome, findsOneWidget);
      await _dispose(t);
    });
  });

  group('Sign-in sheet', () {
    testWidgets('closing on the code step and reopening resumes with the draft',
        (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _sendCode(t, '8031234567');
      await t.enterText(_field, '482');
      await t.pump();

      await _closeSheet(t);
      expect(_sheet, findsNothing);
      expect(run.session.isGuest, isTrue);
      expect(find.text('Posting a job is next in the redesign.'), findsNothing);

      await _postJob(t);
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);
      expect(_fieldText, '482');
      expect(
        _inSheet(find.textContaining('803 123 4567')),
        findsOneWidget,
      );
      await _enterCode(t, '482915');
      await _waitForSheetToClose(t);
      expect(run.session.isSignedIn, isTrue);
      await _dispose(t);
    });

    testWidgets('closing on the details step and reopening resumes there',
        (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      expect(_inSheet(find.text("What's your name?")), findsOneWidget);
      await _closeSheet(t);

      await _postJob(t);
      expect(_inSheet(find.text("What's your name?")), findsOneWidget);
      await t.enterText(_field, 'Ada Obi');
      await t.pump();
      await t.tap(_inSheet(find.text('Create account')));
      await _wait(t, const Duration(milliseconds: 900));
      await _waitForSheetToClose(t);
      expect(run.session.user!.firstName, 'Ada');
      await _dispose(t);
    });

    testWidgets('a wrong code says so, and the right one then works',
        (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _sendCode(t, '8031234567');

      await _enterCode(t, '000000');
      expect(_inSheet(find.text(_wrongCode)), findsOneWidget);
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);
      expect(run.session.isGuest, isTrue);

      // Verify checks the same code again.
      await t.tap(_inSheet(find.text('Verify')));
      await _wait(t, const Duration(milliseconds: 1000));
      expect(_inSheet(find.text(_wrongCode)), findsOneWidget);

      // Editing clears the message; a right code signs in.
      await t.enterText(_field, '48291');
      await t.pump();
      expect(_inSheet(find.text(_wrongCode)), findsNothing);
      await _enterCode(t, '482915');
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      await _waitForSheetToClose(t);
      expect(run.session.isSignedIn, isTrue);
      await _dispose(t);
    });

    testWidgets('"Change" and back return to the number, ready to edit',
        (t) async {
      final run = await _launch(t);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _sendCode(t, '8031234567');

      await t.tapOnText(find.textRange.ofSubstring('Change'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Post your job')), findsOneWidget);
      expect(_fieldText, '803 123 4567');
      expect(run.flow.phone, isNull, reason: 'the old code is dropped');

      await _sendCode(t, '8091234567');
      expect(
        _inSheet(find.textContaining('809 123 4567')),
        findsOneWidget,
      );

      await t.tap(_inSheet(find.bySemanticsLabel('Back')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_fieldText, '809 123 4567');
      await _dispose(t);
    });

    testWidgets('back and "Change" wait while a code is being checked',
        (t) async {
      await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await _sendCode(t, '8031234567');
      AppIconButton back() => t.widget<AppIconButton>(
            _inSheet(
              find.widgetWithIcon(AppIconButton, IconsaxPlusLinear.arrow_left),
            ),
          );

      await t.enterText(_field, '000000');
      await t.pump(const Duration(milliseconds: 100));
      expect(back().onPressed, isNull);
      await _wait(t, const Duration(milliseconds: 1000));
      expect(_inSheet(find.text(_wrongCode)), findsOneWidget);
      expect(back().onPressed, isNotNull);
      await _dispose(t);
    });

    testWidgets('a new code can be sent once the countdown ends', (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      // A code sent a while ago, so the countdown has ended. (The countdown
      // reads the real clock, which pumping doesn't move.)
      run.flow.restoreChallenge(
        '8031234567',
        OtpChallenge(
          phone: '+2348031234567',
          channel: OtpChannel.sms,
          requestId: 'qa',
          resendAvailableAt:
              DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      await _postJob(t);
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);

      await t.tap(_inSheet(find.text('Resend code')));
      await _wait(t, const Duration(milliseconds: 900));
      expect(_inSheet(find.textContaining('New code sent to')), findsOneWidget);
      expect(_inSheet(find.textContaining('Resend code in')), findsOneWidget);

      await _enterCode(t, '482915');
      await _waitForSheetToClose(t);
      expect(run.session.isSignedIn, isTrue);
      await _dispose(t);
    });

    testWidgets("the keyboard's done key completes the number and the name",
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await t.enterText(_field, '8091234567');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await _wait(t, const Duration(milliseconds: 1200));
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);

      await _enterCode(t, '123456');
      await t.enterText(_field, 'Ada Obi');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await _wait(t, const Duration(milliseconds: 900));
      await _waitForSheetToClose(t);
      expect(run.session.user!.firstName, 'Ada');
      expect(_sheet, findsNothing);
      await _dispose(t);
    });

    testWidgets('a tab that needs an account opens the sheet for it',
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      await _openTab(t, IconsaxPlusLinear.calendar_tick);
      expect(find.text('Your bookings live here'), findsOneWidget);
      await _ask(t, 'Sign in or sign up');
      expect(_inSheet(find.text('See your bookings')), findsOneWidget);
      await _signInOnSheet(t, '8031234567');
      expect(run.session.isSignedIn, isTrue);
      expect(find.text('Your bookings live here'), findsNothing);
      expect(find.text('Coming in the redesign'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('"Post a job" asked twice before a frame opens one sheet',
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      final row = find
          .ancestor(
            of: find.text(_postJobRow),
            matching: find.byType(Pressable),
          )
          .first;
      await t.ensureVisible(row);
      await t.pump();
      // Both requests reach AuthGate before the sheet is built. (Two real
      // taps can't: the navigator absorbs pointers in the frame it pushes.)
      final postJob = t.widget<Pressable>(row).onTap!;
      postJob();
      postJob();
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsOneWidget);
      expect(find.text('Post your job'), findsOneWidget);

      await _signInOnSheet(t, '8031234567');
      expect(run.session.isSignedIn, isTrue);
      expect(_sheet, findsNothing, reason: 'no second sheet was queued');
      await _dispose(t);
    });

    testWidgets('a quick double tap on "Post a job" leaves one sheet open',
        (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      final row = find.text(_postJobRow);
      await t.ensureVisible(row);
      await t.pump();
      final at = t.getCenter(row);
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 120));
      await t.tapAt(at);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_sheet, findsOneWidget);
      expect(run.session.isGuest, isTrue);
      await _dispose(t);
    });

    testWidgets('the details step leads back to the number', (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      expect(_inSheet(find.text("What's your name?")), findsOneWidget);
      await t.tap(_inSheet(find.bySemanticsLabel('Back')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_fieldText, '809 123 4567');
      expect(run.flow.needsDetails, isFalse);
      await _dispose(t);
    });

    testWidgets('system back on the code step returns to the number',
        (t) async {
      await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await _sendCode(t, '8031234567');
      await t.binding.handlePopRoute();
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsOneWidget);
      expect(_fieldText, '803 123 4567');
      await _dispose(t);
    });

    testWidgets('signing in from welcome shows success, then lands on home',
        (t) async {
      final run = await _launch(t);
      await _signInFromWelcome(t);
      expect(_inSheet(find.text('Welcome back')), findsOneWidget);

      await _sendCode(t, '8031234567');
      await _enterCode(t, '482915');
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      // The home is already there under the success moment.
      expect(_welcome, findsNothing);
      expect(_clientHome, findsOneWidget);

      await _waitForSheetToClose(t);
      expect(_sheet, findsNothing);
      expect(_welcome, findsNothing);
      expect(run.session.hasOnboarded, isTrue);
      expect(_clientHome, findsOneWidget);
      expect(_herBooking, findsOneWidget);
      await _dispose(t);
    });

    testWidgets('an artisan signing in from welcome lands on the dashboard',
        (t) async {
      final run = await _launch(t);
      await _signInFromWelcome(t);
      await _signInOnSheet(t, '8059876543');
      expect(_welcome, findsNothing);
      expect(run.session.role, UserRole.artisan);
      expect(_availability('Available'), findsOneWidget);
      expect(_hisEarnings, findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('closing the sign-in sheet from welcome carries on exploring',
        (t) async {
      final run = await _launch(t);
      await _signInFromWelcome(t);
      await _closeSheet(t);
      expect(_welcome, findsNothing);
      expect(run.session.hasOnboarded, isTrue);
      expect(run.session.isGuest, isTrue);
      expect(_clientHome, findsOneWidget);
      await _dispose(t);
    });

    testWidgets('closing the sheet mid-check on welcome still ends on home',
        (t) async {
      final run = await _launch(t);
      await _signInFromWelcome(t);
      await _sendCode(t, '8031234567');
      await t.enterText(_field, '482915');
      await t.pump(const Duration(milliseconds: 100));
      await _closeSheet(t);
      await _wait(t, const Duration(milliseconds: 1500));
      expect(run.session.isSignedIn, isTrue);
      expect(_welcome, findsNothing);
      expect(_clientHome, findsOneWidget);
      await _dispose(t);
    });
  });

  group('Restart', () {
    testWidgets('keeps sign-in, role, onboarding and area', (t) async {
      final first = await _launch(t);
      await _enter(t, UserRole.client);
      await _ask(t, 'Sign in');
      await _signInOnSheet(t, '8031234567');
      await t.tap(_pill('Wuse 2'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.enterText(_field, 'gwar');
      await t.pump();
      await t.tap(_inSheet(find.text('Gwarinpa')));
      await _wait(t, const Duration(milliseconds: 800));
      expect(_pill('Gwarinpa'), findsOneWidget);

      final second = await _launch(t, prefs: first.prefs);
      expect(_welcome, findsNothing);
      expect(second.session.hasOnboarded, isTrue);
      expect(second.session.isSignedIn, isTrue);
      expect(second.session.user!.firstName, 'Chidinma');
      expect(second.session.role, UserRole.client);
      expect(second.session.area, 'Gwarinpa');
      expect(_herBooking, findsOneWidget);
      expect(_pill('Gwarinpa'), findsOneWidget);
      expect(second.artisans.areas, ['Gwarinpa']);
      await _dispose(t);
    });

    testWidgets('keeps a guest artisan on the artisan side', (t) async {
      final first = await _launch(t);
      await _enter(t, UserRole.artisan);
      final second = await _launch(t, prefs: first.prefs);
      expect(_welcome, findsNothing);
      expect(second.session.isGuest, isTrue);
      expect(second.session.role, UserRole.artisan);
      expect(_artisanGuestHome, findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a guest who signs out and restarts stays a guest', (t) async {
      final first = await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
      );
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Sign out');
      await _wait(t, const Duration(milliseconds: 400));
      final second = await _launch(t, prefs: first.prefs);
      expect(_welcome, findsNothing);
      expect(second.session.isGuest, isTrue);
      expect(second.session.role, UserRole.artisan);
      await _dispose(t);
    });
  });

  group('New accounts', () {
    testWidgets('a new client keeps "Abuja" and sees no one else\'s booking',
        (t) async {
      final run = await _launch(t, height: 1800);
      await _enter(t, UserRole.client);
      await _postJob(t);
      await _signUpClient(t, 'Ada Obi');
      expect(run.session.area, isNull);
      expect(_pill('Abuja'), findsOneWidget);
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(run.artisans.areas, ['Abuja']);
      // A first run: nothing booked, nobody hired before.
      expect(_herBooking, findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Next booking')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Book .* again\$')), findsNothing);
      expect(find.textContaining('You hired'), findsNothing);
      expect(find.text('Emeka Nwosu'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets("a new artisan's availability names the area jobs come from",
        (t) async {
      await _launch(t, height: 2000);
      await _enter(t, UserRole.client);
      await t.tap(_pill('Abuja'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.enterText(_field, 'gwar');
      await t.pump();
      await t.tap(_inSheet(find.text('Gwarinpa')));
      await _wait(t, const Duration(milliseconds: 800));
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Find work on RijHub');
      await _wait(t, const Duration(milliseconds: 400));
      await _openTab(t, IconsaxPlusLinear.home_2);
      await _quoteOn(t, 'Socket sparking in the kitchen');
      await _signUpArtisan(t, 'Tunde Bakare', ['AC repair']);
      await _wait(t, const Duration(milliseconds: 800));
      // A new profile starts off, until the artisan says otherwise.
      expect(_availability('Off'), findsOneWidget);
      await t.tap(_availability('Off'));
      await _wait(t, const Duration(milliseconds: 600));
      final today =
          MockData.demand(area: 'Gwarinpa', categoryId: 'ac').postedToday;
      expect(
        _inSheet(find.text('$today AC repair jobs posted today near Gwarinpa')),
        findsOneWidget,
      );
      // Clients can book them once their ID is checked; until then the
      // sheet says so and offers the check.
      expect(_inSheet(find.text('Verify your ID first')), findsOneWidget);
      expect(_inSheet(find.text('Verify your ID')), findsOneWidget);
      await t.tap(_inSheet(find.text('Available now')));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Your availability')), findsOneWidget);
      await _dispose(t);
    });

    testWidgets("a brand-new artisan doesn't see someone else's earnings",
        (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.artisan),
        height: 1800,
      );
      await _quoteOn(t, 'Socket sparking in the kitchen');
      await _signUpArtisan(t, 'Tunde Bakare', ['AC repair']);
      await _wait(t, const Duration(milliseconds: 800));
      expect(run.session.user!.firstName, 'Tunde');
      // No money, bookings, requests or week to show yet.
      expect(_hisEarnings, findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Earned this week')), findsNothing);
      expect(find.textContaining('TODAY'), findsNothing);
      expect(find.byType(ArtisanRequestCard), findsNothing);
      expect(find.textContaining('This week'), findsNothing);
      // Off, with the ID check first and the rest of setup below the jobs.
      expect(_availability('Off'), findsOneWidget);
      expect(_idBanner, findsOneWidget);
      // Sign-up already verified the phone and took the trades.
      expect(find.text('2/6'), findsOneWidget);
      expect(find.text('Set your work area'), findsOneWidget);
      // Jobs in their trade, ready to quote on.
      expect(find.text('New jobs for you'), findsOneWidget);
      expect(_filter(t, 'My trades').selected, isTrue);
      await _dispose(t);
    });

    testWidgets(
        'signing in again with a number just registered says welcome '
        'back', (t) async {
      final run = await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await _signUpClient(t, 'Ada Obi');
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Sign out');
      await _wait(t, const Duration(milliseconds: 400));
      await _ask(t, 'Sign in or sign up');
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      expect(_inSheet(find.text('Welcome back, Ada.')), findsOneWidget);
      await _waitForSheetToClose(t);
      expect(run.session.user!.firstName, 'Ada');
      await _dispose(t);
    });

    testWidgets('a new client still has no booking after a restart', (t) async {
      final first = await _launch(t, prefs: await _installed(UserRole.client));
      await _postJob(t);
      await _signUpClient(t, 'Ada Obi');

      final second = await _launch(t, prefs: first.prefs, height: 1800);
      expect(second.session.user!.firstName, 'Ada');
      expect(_bell, findsOneWidget);
      expect(_herBooking, findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Next booking')), findsNothing);
      await _dispose(t);
    });
  });

  group('Profile tab offline', () {
    testWidgets('signing out works without a connection', (t) async {
      final run = await _launch(
        t,
        prefs: await _installed(UserRole.client, signedIn: true),
        auth: _OfflineSignOut(),
      );
      await _openTab(t, IconsaxPlusLinear.profile_circle);
      await _tapText(t, 'Sign out');
      await _wait(t, const Duration(milliseconds: 400));
      expect(run.session.isGuest, isTrue);
      expect(find.text('Join RijHub'), findsOneWidget);
      await _dispose(t);
    });
  });

  group('Section links', () {
    testWidgets('"See all" on the client home takes taps just off the row',
        (t) async {
      await _launch(t, prefs: await _installed(UserRole.client), height: 1800);
      for (final below in [false, true]) {
        final link = find.text('See all').first;
        final header = t.getRect(
          find.ancestor(of: link, matching: find.byType(SectionHeader)),
        );
        final x = t.getCenter(link).dx;
        await t.tapAt(Offset(x, below ? header.bottom + 8 : header.top - 8));
        await _wait(t, const Duration(milliseconds: 600));
        expect(find.text('Coming in the redesign'), findsOneWidget);
        await _openTab(t, IconsaxPlusLinear.home_2);
      }
      await _dispose(t);
    });

    testWidgets(
        '"See all" on the artisan dashboard takes taps in the gap above '
        'its row', (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
        height: 2000,
      );
      // The chips start right under the title, so the link's touch band
      // reaches up into the gap instead.
      for (final above in [8.0, 20.0]) {
        final link = find.text('See all').first;
        final header = t.getRect(
          find.ancestor(of: link, matching: find.byType(ArtisanSectionHeader)),
        );
        final x = t.getCenter(link).dx;
        await t.tapAt(Offset(x, header.top - above));
        await _wait(t, const Duration(milliseconds: 600));
        expect(find.text('Coming in the redesign'), findsOneWidget);
        expect(find.text('Browse every open job near you and send quotes.'),
            findsOneWidget);
        await _openTab(t, IconsaxPlusLinear.home_2);
      }
      await _dispose(t);
    });
  });

  group('Screen readers and motion', () {
    testWidgets('a screen reader can switch tabs', (t) async {
      final semantics = t.ensureSemantics();
      await _launch(t, prefs: await _installed(UserRole.client));
      t.semantics.tap(find.semantics.byLabel('Explore'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Coming in the redesign'), findsOneWidget);
      await _dispose(t);
      semantics.dispose();
    });

    testWidgets('the signed-in client home opens with reduced motion',
        (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _launch(t,
          prefs: await _installed(UserRole.client, signedIn: true));
      expect(t.takeException(), isNull);
      expect(_herBooking, findsOneWidget);
      await _dispose(t);
    });
  });

  // Each test below is the expected behaviour for an open QA finding. They
  // fail today; drop the `skip` once the finding is fixed.
  group('Quick double taps on what opens a sheet', () {
    // The second tap lands on the scrim as the sheet rises; every sheet
    // wraps its content in DoubleTapGuard so that tap can't close it.
    testWidgets('a quick double tap on the area pill leaves the picker open',
        (t) async {
      await _launch(t, prefs: await _installed(UserRole.client));
      final at = t.getCenter(_pill('Abuja'));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 120));
      await t.tapAt(at);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_inSheet(find.text('Choose your area')), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a quick double tap on a job leaves its sheet open', (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.artisan),
        height: 1800,
      );
      final at = t.getCenter(find.text('Fix a leaking kitchen tap'));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 120));
      await t.tapAt(at);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_inSheet(find.text('Send quote')), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('a quick double tap on availability leaves its sheet open',
        (t) async {
      await _launch(
        t,
        prefs: await _installed(UserRole.artisan, signedIn: true),
      );
      final at = t.getCenter(_availability('Available'));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 120));
      await t.tapAt(at);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_inSheet(find.text('Your availability')), findsOneWidget);
      await _dispose(t);
    });
  });
}
