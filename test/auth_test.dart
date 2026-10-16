// The sign-in sheet in the real app (router, session, AuthGate(showAuthSheet))
// on mock data: going back a step, the double tap that opened it, the role
// question for new numbers from welcome, the pinned button on the name step
// and the success moment under reduced motion and screen readers.
//
// The mocks wait with Future.delayed, which completes as the test pumps fake
// time past it, so these pump rather than await.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/auth/auth_sheet.dart';
import 'package:rijhub/features/onboarding/welcome_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mock, except that the first code it is asked for fails to send.
class _FirstSendFails extends MockAuthRepository {
  _FirstSendFails({super.accounts});

  var _sends = 0;

  @override
  Future<OtpChallenge> requestCode(
    String phone, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    if (_sends++ == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      throw const AuthException('No connection. Check your data and retry.');
    }
    return super.requestCode(phone, channel: channel);
  }
}

class _Run {
  _Run(this.session, this.flow);

  final SessionController session;
  final AuthFlowController flow;
}

/// Starts the app as `main.dart` does, on a fresh install unless [prefs]
/// says otherwise, and waits past the splash.
Future<_Run> _launch(
  WidgetTester t, {
  SharedPreferences? prefs,
  bool firstSendFails = false,
  double width = 390,
  double height = 844,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(width * 3, height * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);

  if (prefs == null) {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }
  final accounts = MockAccounts();
  final deps = AppDependencies(
    auth: firstSendFails
        ? _FirstSendFails(accounts: accounts)
        : MockAuthRepository(accounts: accounts),
    catalog: MockCatalogRepository(),
    artisans: MockArtisanRepository(),
    jobs: MockJobRepository(accounts: accounts),
    bookings: MockBookingRepository(accounts: accounts),
    artisanDashboard: MockArtisanDashboardRepository(accounts: accounts),
  );
  final session = SessionController(prefs: prefs, auth: deps.auth)..restore();
  final flow = AuthFlowController(auth: deps.auth, session: session);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: flow,
    authGate: AuthGate(showAuthSheet),
  ));
  await _wait(t, const Duration(milliseconds: 2200));
  return _Run(session, flow);
}

/// A fresh install that has been through welcome as a guest of [role].
Future<SharedPreferences> _guest(UserRole role) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await SessionController(prefs: prefs, auth: MockAuthRepository())
      .continueAsGuest(role);
  return prefs;
}

/// Pumps [total] of fake time in short frames.
Future<void> _wait(
  WidgetTester t, [
  Duration total = const Duration(milliseconds: 1500),
]) async {
  const frame = Duration(milliseconds: 50);
  for (var waited = Duration.zero; waited < total; waited += frame) {
    await t.pump(frame);
  }
}

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _wait(t, const Duration(milliseconds: 500));
}

Finder get _sheet => find.byType(BottomSheet);

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

Finder get _field => _inSheet(find.byType(TextField));

String get _fieldText =>
    (_field.evaluate().single.widget as TextField).controller!.text;

Finder get _back => _inSheet(find.bySemanticsLabel('Back'));

AppButton _button(WidgetTester t, String label) =>
    t.widget<AppButton>(_inSheet(find.widgetWithText(AppButton, label)));

/// The welcome screen's headline, which only it shows.
/// The welcome sheet first-time visitors see over the home.
Finder get _welcomeHeadline => find.byType(WelcomeSheet);

/// The client home's way to post a job: the row under the artisans.
const _postJobRow = 'Not sure who to pick?';

Future<void> _ask(WidgetTester t, String action) async {
  final button = find.text(action).first;
  await t.ensureVisible(button);
  await t.pump();
  await t.tap(button);
  await _wait(t, const Duration(milliseconds: 600));
}

/// Opens the job called [title] from the artisan home and taps its "Send
/// quote", which asks a guest for a profile.
Future<void> _quoteOn(WidgetTester t, String title) async {
  await _ask(t, title);
  await t.tap(_inSheet(find.text('Send quote')));
  await _wait(t, const Duration(milliseconds: 600));
}

Future<void> _sendCode(WidgetTester t, String phone) async {
  await t.enterText(_field, phone);
  await t.pump();
  await t.tap(_inSheet(find.text('Send code')));
  await _wait(t, const Duration(milliseconds: 1200));
}

Future<void> _enterCode(WidgetTester t, String code) async {
  await t.enterText(_field, code);
  await t.pump();
  await _wait(t, const Duration(milliseconds: 1300));
}

/// Opens the sheet from the welcome sheet's "Sign in" and verifies a
/// number that has no account.
Future<void> _newNumberFromWelcome(WidgetTester t) async {
  await t.tap(
    find.descendant(of: _welcomeHeadline, matching: find.text('Sign in')),
  );
  await _wait(t, const Duration(milliseconds: 600));
  await _sendCode(t, '8091234567');
  await _enterCode(t, '123456');
  // The trades load.
  await _wait(t, const Duration(milliseconds: 400));
}

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  group('Opening and closing', () {
    testWidgets('a quick double tap on "Post a job" leaves one sheet open',
        (t) async {
      final run = await _launch(t, prefs: await _guest(UserRole.client));
      final button = find.text(_postJobRow);
      await t.ensureVisible(button);
      await t.pump();
      final at = t.getCenter(button);
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 120));
      // Lands on the scrim, which is rising under the finger.
      await t.tapAt(at);
      await _wait(t, const Duration(milliseconds: 800));
      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.text('Post your job')), findsOneWidget);
      expect(run.session.isGuest, isTrue);

      // A deliberate tap on the scrim later still closes it.
      await t.tapAt(const Offset(195, 60));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsNothing);
      await _dispose(t);
    });

    testWidgets('Android back closes the sheet from the number step',
        (t) async {
      await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await t.binding.handlePopRoute();
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsNothing);
      await _dispose(t);
    });

    testWidgets('reopening after a failed send keeps the number', (t) async {
      final run = await _launch(
        t,
        prefs: await _guest(UserRole.client),
        firstSendFails: true,
      );
      await _ask(t, _postJobRow);
      await _sendCode(t, '8031234567');
      expect(_inSheet(find.textContaining('No connection')), findsOneWidget);
      await t.tap(_inSheet(find.bySemanticsLabel('Close')));
      await _wait(t, const Duration(milliseconds: 600));

      await _ask(t, _postJobRow);
      expect(_fieldText, '803 123 4567');
      expect(_button(t, 'Send code').onPressed, isNotNull);
      await t.tap(_inSheet(find.text('Send code')));
      await _wait(t, const Duration(milliseconds: 1200));
      expect(_inSheet(find.text('Enter the code')), findsOneWidget);
      expect(run.flow.phone, '8031234567');
      await _dispose(t);
    });
  });

  group('Going back a step', () {
    testWidgets('the name step leads back to the number', (t) async {
      final run = await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      expect(_inSheet(find.text("What's your name?")), findsOneWidget);

      await t.tap(_back);
      await _wait(t, const Duration(milliseconds: 600));
      expect(_inSheet(find.text('Post your job')), findsOneWidget);
      expect(_fieldText, '809 123 4567');
      expect(run.flow.needsDetails, isFalse);

      // Closed and reopened, it asks for a number again.
      await t.tap(_inSheet(find.bySemanticsLabel('Close')));
      await _wait(t, const Duration(milliseconds: 600));
      await _ask(t, _postJobRow);
      expect(_inSheet(find.text('Post your job')), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('Android back on the code step returns to the number',
        (t) async {
      await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8031234567');
      await t.binding.handlePopRoute();
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.text('Post your job')), findsOneWidget);
      expect(_fieldText, '803 123 4567');
      await _dispose(t);
    });

    testWidgets('Android back on the name step returns to the number',
        (t) async {
      await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      await t.binding.handlePopRoute();
      await _wait(t, const Duration(milliseconds: 600));
      expect(_sheet, findsOneWidget);
      expect(_fieldText, '809 123 4567');
      await _dispose(t);
    });

    testWidgets('back waits while the account is being created', (t) async {
      final run = await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      AppIconButton back() => t.widget<AppIconButton>(
            _inSheet(
              find.widgetWithIcon(AppIconButton, IconsaxPlusLinear.arrow_left),
            ),
          );
      expect(back().onPressed, isNotNull);

      await t.enterText(_field, 'Ada Obi');
      await t.pump();
      await t.tap(_inSheet(find.text('Create account')));
      await t.pump(const Duration(milliseconds: 100));
      expect(back().onPressed, isNull);
      await t.binding.handlePopRoute();
      await _wait(t, const Duration(milliseconds: 900));
      expect(run.session.user!.firstName, 'Ada');
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      await _dispose(t);
    });
  });

  group('A new number from welcome', () {
    testWidgets('is asked how it will be used, and can become an artisan',
        (t) async {
      final run = await _launch(t);
      await _newNumberFromWelcome(t);
      expect(_inSheet(find.text('Create your account')), findsOneWidget);
      expect(_inSheet(find.text('How will you use RijHub?')), findsOneWidget);
      // Nothing is picked for them, and nothing else is asked yet.
      expect(_field, findsNothing);
      expect(_button(t, 'Create account').onPressed, isNull);

      await t.tap(_inSheet(find.text('Find work')));
      await _wait(t, const Duration(milliseconds: 400));
      expect(_inSheet(find.text('Full name')), findsOneWidget);
      expect(_inSheet(find.text('What do you do?')), findsOneWidget);
      await t.enterText(_field, 'Tunde Bakare');
      await t.pump();
      expect(_button(t, 'Create profile').onPressed, isNull);
      await t.tap(_inSheet(find.text('Generator')));
      await t.pump();
      await t.tap(_inSheet(find.text('Create profile')));
      await _wait(t, const Duration(milliseconds: 900));
      expect(_inSheet(find.text('Welcome, Tunde.')), findsOneWidget);
      await _wait(t, const Duration(milliseconds: 1400));

      expect(_sheet, findsNothing);
      expect(run.session.user!.role, UserRole.artisan);
      expect(run.session.role, UserRole.artisan);
      expect(_welcomeHeadline, findsNothing);
      expect(find.text('Jobs'), findsOneWidget);
      // Their own dashboard: off until the ID check, with their trade.
      expect(
        find.bySemanticsLabel(RegExp(r'^Availability\. Off')),
        findsOneWidget,
      );
      expect(run.session.user!.tradeIds, ['generator']);
      await _dispose(t);
    });

    testWidgets('can become a client', (t) async {
      final run = await _launch(t);
      await _newNumberFromWelcome(t);
      await t.tap(_inSheet(find.text('Hire an artisan')));
      await _wait(t, const Duration(milliseconds: 400));
      expect(_inSheet(find.text('Your name')), findsOneWidget);
      expect(_inSheet(find.text('What do you do?')), findsNothing);
      await t.enterText(_field, 'Ada');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await _wait(t, const Duration(milliseconds: 900));
      await _wait(t, const Duration(milliseconds: 1400));

      expect(_sheet, findsNothing);
      expect(run.session.user!.role, UserRole.client);
      expect(_welcomeHeadline, findsNothing);
      // The client home, signed in: the bell where "Sign in" was.
      expect(find.text('What needs fixing?'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Sign in'), findsNothing);
      await _dispose(t);
    });

    testWidgets('a number from inside the app is not asked', (t) async {
      await _launch(t, prefs: await _guest(UserRole.artisan), height: 1800);
      await _quoteOn(t, 'Socket sparking in the kitchen');
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      await _wait(t, const Duration(milliseconds: 400));
      expect(_inSheet(find.text('Set up your profile')), findsOneWidget);
      expect(_inSheet(find.text('How will you use RijHub?')), findsNothing);
      expect(_inSheet(find.text('Full name')), findsOneWidget);
      await _dispose(t);
    });
  });

  group('Name step', () {
    testWidgets('clients are asked only for their name', (t) async {
      await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      expect(_inSheet(find.text('Your name')), findsOneWidget);
      expect(_inSheet(find.text('Full name')), findsNothing);
      await _dispose(t);
    });

    testWidgets("on a small phone the artisan's button is in view", (t) async {
      final run = await _launch(
        t,
        prefs: await _guest(UserRole.artisan),
        width: 375,
        height: 667,
      );
      // The header's, as the jobs to quote on are below the fold here.
      await _ask(t, 'Sign in');
      await _sendCode(t, '8091234567');
      await _enterCode(t, '123456');
      await _wait(t, const Duration(milliseconds: 400));
      await t.enterText(_field, 'Tunde Bakare');
      FocusManager.instance.primaryFocus?.unfocus();
      await _wait(t, const Duration(milliseconds: 300));
      // The list of trades runs on out of sight...
      final content = t.getRect(_inSheet(find.byType(SingleChildScrollView)));
      expect(
        t.getRect(_inSheet(find.text('TV & decoder'))).top,
        greaterThan(content.bottom),
      );
      // ...while the button stays above it, tappable where it is.
      final button = t.getRect(
        _inSheet(find.widgetWithText(AppButton, 'Create profile')),
      );
      expect(button.bottom, lessThanOrEqualTo(667));
      await t.tap(_inSheet(find.text('AC repair')));
      await t.pump();
      await t.tapAt(button.center);
      await _wait(t, const Duration(milliseconds: 900));
      expect(run.session.user!.role, UserRole.artisan);
      await _dispose(t);
    });
  });

  group('Success', () {
    testWidgets('reduced motion still shows "You\'re all set" before closing',
        (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final run = await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8031234567');
      await t.enterText(_field, '482915');
      await _wait(t, const Duration(milliseconds: 1000));
      expect(run.session.isSignedIn, isTrue);
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      await _wait(t, const Duration(milliseconds: 1000));
      expect(_sheet, findsNothing);
      await _dispose(t);
    });

    testWidgets('a screen reader has time to say it before the sheet closes',
        (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _launch(t, prefs: await _guest(UserRole.client));
      await _ask(t, _postJobRow);
      await _sendCode(t, '8031234567');
      await _enterCode(t, '482915');
      await _wait(t, const Duration(milliseconds: 2000));
      expect(_inSheet(find.text("You're all set")), findsOneWidget);
      await _wait(t, const Duration(milliseconds: 1500));
      expect(_sheet, findsNothing);
      await _dispose(t);
    });
  });

  testWidgets("a message's last two words wrap together", (t) async {
    await _launch(t, prefs: await _guest(UserRole.client));
    await _ask(t, _postJobRow);
    expect(
      _inSheet(find.text(
        'Add your phone number so artisans can send you quotes.',
      )),
      findsOneWidget,
    );
    await _dispose(t);
  });
}
