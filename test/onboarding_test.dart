// The splash, welcome screen and tab shell: what people see, and what
// screen readers and switches can reach.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/routes.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/features/auth/auth_sheet.dart';
import 'package:rijhub/features/onboarding/splash_screen.dart';
import 'package:rijhub/features/onboarding/welcome_sheet.dart';
import 'package:rijhub/features/shell/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records sign-in requests instead of showing the sheet.
class _FakeSheet {
  final prompts = <AuthPrompt>[];

  Future<bool> present(BuildContext context, AuthPrompt prompt) async {
    prompts.add(prompt);
    return false;
  }
}

/// The app on mock data, at [location]. A fresh install unless [guestAs]
/// or [signedInAs] is given.
Future<(SessionController, _FakeSheet)> _pumpApp(
  WidgetTester t, {
  UserRole? guestAs,
  UserRole? signedInAs,
  String? location,
  AuthPresenter? presenter,
  double width = 390,
  double height = 844,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(width * 3, height * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final deps = AppDependencies.mock();
  final session = SessionController(prefs: prefs, auth: deps.auth);
  if (guestAs != null) await session.continueAsGuest(guestAs);
  if (signedInAs != null) await session.signIn(MockData.sampleUser(signedInAs));
  final sheet = _FakeSheet();
  await t.pumpWidget(RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: AuthFlowController(auth: deps.auth, session: session),
    authGate: AuthGate(presenter ?? sheet.present),
    initialLocation: location,
  ));
  await _wait(t);
  return (session, sheet);
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

Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _wait(t, const Duration(milliseconds: 500));
}

/// Lays text out in Inter, as on a device.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await loader.load();
}

SemanticsData _data(FinderBase<SemanticsNode> finder) =>
    finder.evaluate().single.getSemanticsData();

/// The node a screen reader reads, as it reads it.
SemanticsFinder _node(bool Function(SemanticsData data) test, String name) =>
    find.semantics.byPredicate(
      (node) => !node.isMergedIntoParent && test(node.getSemanticsData()),
      describeMatch: (_) => name,
    );

/// The bottom bar's tab called [label].
SemanticsFinder _tab(String label) => _node(
      (data) => data.role == SemanticsRole.tab && data.label == label,
      'the "$label" tab',
    );

/// The heading that reads [label].
SemanticsFinder _heading(String label) => _node(
      (data) => data.flagsCollection.isHeader && data.label == label,
      'the "$label" heading',
    );

void main() {
  setUpAll(_loadInter);

  group('Tab bar', () {
    testWidgets('a screen reader or switch can open every tab', (t) async {
      final semantics = t.ensureSemantics();
      await _pumpApp(t, guestAs: UserRole.client, location: Routes.home);

      final bar = find.semantics
          .byPredicate(
            (node) => node.getSemanticsData().role == SemanticsRole.tabBar,
          )
          .evaluate()
          .single;
      expect(bar.childrenCount, 5);

      const screens = {
        'Explore': 'Coming in the redesign',
        'Bookings': 'Your bookings live here',
        'Messages': 'Talk to artisans',
        'Profile': 'Join RijHub',
      };
      var position = 2;
      for (final MapEntry(key: label, value: shows) in screens.entries) {
        expect(_data(_tab(label)).flagsCollection.isSelected, Tristate.isFalse);
        t.semantics.tap(_tab(label));
        await _wait(t, const Duration(milliseconds: 600));
        expect(find.text(shows), findsOneWidget, reason: label);
        final tab = _data(_tab(label));
        expect(tab.flagsCollection.isSelected, Tristate.isTrue);
        expect(tab.flagsCollection.isButton, isTrue);
        expect(tab.hint, 'Tab $position of 5');
        position++;
      }
      t.semantics.tap(_tab('Home'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_data(_tab('Home')).flagsCollection.isSelected, Tristate.isTrue);
      expect(_data(_tab('Home')).hint, 'Tab 1 of 5');

      await _dispose(t);
      semantics.dispose();
    });

    for (final role in UserRole.values) {
      testWidgets(
          'labels keep to one line, well apart, at the largest text on a '
          '360-wide phone (${role.name})', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpApp(
          t,
          signedInAs: role,
          location: Routes.account,
          width: 360,
          height: 640,
        );
        expect(t.takeException(), isNull);

        final labels = role == UserRole.client
            ? ['Home', 'Explore', 'Bookings', 'Messages', 'Profile']
            : ['Home', 'Jobs', 'Schedule', 'Messages', 'Profile'];
        final bar = find.byType(Row).hitTestable().last;
        Rect label(String text) => t.getRect(
              find.descendant(of: bar, matching: find.text(text)),
            );
        final caption = AppText.caption.fontSize!;
        for (var i = 0; i < labels.length; i++) {
          final rect = label(labels[i]);
          // One line, and no taller than the bar's text-size limit allows.
          expect(rect.height, lessThan(caption * 1.15 * 1.5),
              reason: labels[i]);
          if (i > 0) {
            final gap = rect.left - label(labels[i - 1]).right;
            expect(gap, greaterThanOrEqualTo(8), reason: labels[i]);
          }
        }
        await _dispose(t);
      });
    }

    testWidgets('claims no unread messages before messaging exists', (t) async {
      final semantics = t.ensureSemantics();
      await _pumpApp(t, signedInAs: UserRole.client, location: Routes.home);
      expect(
        _node((data) => data.label.contains('unread'), 'an unread count'),
        findsNothing,
      );
      expect(_tab('Messages'), findsOne);
      await _dispose(t);
      semantics.dispose();
    });

    testWidgets('Explore keeps the magnifier when it is the open tab',
        (t) async {
      await _pumpApp(t, guestAs: UserRole.client, location: Routes.explore);
      expect(find.byIcon(IconsaxPlusBold.search_normal_1), findsNothing);
      // The tab and the page both show it.
      expect(find.byIcon(IconsaxPlusLinear.search_normal_1), findsNWidgets(2));
      await _dispose(t);
    });
  });

  group('Tabs that need an account', () {
    testWidgets('guest artisans are asked to create a profile', (t) async {
      final (_, sheet) = await _pumpApp(
        t,
        guestAs: UserRole.artisan,
        location: Routes.bookings,
      );
      expect(find.text('Your schedule lives here'), findsOneWidget);
      await t.tap(find.text('Create your free profile'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(sheet.prompts.single, AuthPrompt.joinAsArtisan);
      await _dispose(t);
    });

    testWidgets('titles are headings', (t) async {
      final semantics = t.ensureSemantics();
      await _pumpApp(t, guestAs: UserRole.client, location: Routes.messages);
      expect(_heading('Messages'), findsOne);
      t.semantics.tap(_tab('Bookings'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(_heading('Bookings'), findsOne);
      await _dispose(t);
      semantics.dispose();
    });
  });

  group('Profile tab', () {
    testWidgets('shows the phone number as people write it, read once',
        (t) async {
      final semantics = t.ensureSemantics();
      await _pumpApp(t, signedInAs: UserRole.client, location: Routes.account);
      expect(find.text('+234 803 123 4567'), findsOneWidget);
      final card = _data(
        _node((data) => data.label.contains('Chidinma'), 'the profile card'),
      );
      expect(card.label, 'Chidinma Okafor\n+234 803 123 4567\nClient');
      expect(card.flagsCollection.isImage, isFalse);
      await _dispose(t);
      semantics.dispose();
    });

    testWidgets('a guest joins with a prompt for new and returning people',
        (t) async {
      final semantics = t.ensureSemantics();
      final (_, sheet) = await _pumpApp(
        t,
        guestAs: UserRole.client,
        location: Routes.account,
      );
      expect(_heading('Profile'), findsOne);
      // The card's title is a heading of its own, not its whole text.
      expect(_heading('Join RijHub'), findsOne);
      await t.tap(find.text('Sign in or sign up'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(sheet.prompts.single, AuthPrompt.join);
      await _dispose(t);
      semantics.dispose();
    });
  });

  group('Welcome', () {
    Finder inWelcome(Finder finder) =>
        find.descendant(of: find.byType(WelcomeSheet), matching: finder);

    testWidgets(
        'first launch opens on the guest home, with the welcome over it',
        (t) async {
      final semantics = t.ensureSemantics();
      final (session, sheet) = await _pumpApp(t);
      expect(session.hasOnboarded, isFalse);
      expect(find.byType(WelcomeSheet), findsOneWidget);
      expect(
        _heading("Abuja's verified artisans, one tap away"),
        findsOne,
      );
      expect(inWelcome(find.text('Explore as a guest')), findsOneWidget);
      expect(inWelcome(find.text('Find work as an artisan')), findsOneWidget);
      // The real home is already there behind the sheet.
      expect(find.byType(AppShell), findsOneWidget);
      expect(sheet.prompts, isEmpty);
      await _dispose(t);
      semantics.dispose();
    });

    testWidgets('exploring lets people in as a guest client', (t) async {
      final (session, sheet) = await _pumpApp(t);
      await t.tap(inWelcome(find.text('Explore as a guest')));
      await _wait(t);
      expect(session.hasOnboarded, isTrue);
      expect(session.isGuest, isTrue);
      expect(session.role, UserRole.client);
      expect(find.byType(WelcomeSheet), findsNothing);
      expect(sheet.prompts, isEmpty);
      await _dispose(t);
    });

    testWidgets('closing the welcome is exploring too', (t) async {
      final (session, _) = await _pumpApp(t);
      // A tap on the dimmed home above the sheet.
      await t.tapAt(const Offset(195, 120));
      await _wait(t);
      expect(session.hasOnboarded, isTrue);
      expect(session.role, UserRole.client);
      expect(find.byType(WelcomeSheet), findsNothing);
      await _dispose(t);
    });

    testWidgets('artisans go straight to jobs', (t) async {
      final (session, sheet) = await _pumpApp(t);
      await t.tap(inWelcome(find.text('Find work as an artisan')));
      await _wait(t);
      expect(session.role, UserRole.artisan);
      expect(session.isGuest, isTrue);
      expect(find.text('Jobs near you'), findsOneWidget);
      expect(sheet.prompts, isEmpty);
      await _dispose(t);
    });

    testWidgets('returning people sign in from the corner', (t) async {
      final (session, sheet) = await _pumpApp(t);
      await t.tap(inWelcome(find.text('Sign in')));
      await _wait(t);
      expect(sheet.prompts.single, AuthPrompt.signIn);
      expect(session.hasOnboarded, isTrue);
      await _dispose(t);
    });

    testWidgets('people who have been here before go straight in', (t) async {
      await _pumpApp(t, guestAs: UserRole.client);
      expect(find.byType(WelcomeSheet), findsNothing);
      await _dispose(t);
    });

    testWidgets(
        'closing the sign-in sheet while the code is checked still '
        'ends signed in, on home', (t) async {
      final (session, _) = await _pumpApp(t, presenter: showAuthSheet);
      await t.tap(inWelcome(find.text('Sign in')));
      await _wait(t, const Duration(milliseconds: 600));
      final sheet = find.byType(BottomSheet);
      final field =
          find.descendant(of: sheet, matching: find.byType(TextField));
      await t.enterText(field.first, '8031234567');
      await t.pump();
      await t.tap(find.descendant(of: sheet, matching: find.text('Send code')));
      await _wait(t, const Duration(milliseconds: 1200));
      await t.enterText(field.first, '482915');
      await t.pump(const Duration(milliseconds: 100));
      // Closed while the mock is still checking the code.
      await t.tap(
        find.descendant(of: sheet, matching: find.bySemanticsLabel('Close')),
      );
      await _wait(t, const Duration(milliseconds: 1500));
      expect(session.isSignedIn, isTrue);
      expect(find.byType(WelcomeSheet), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
      await _dispose(t);
    });
  });

  group('Splash', () {
    testWidgets("starts fully drawn, at the launch image's size", (t) async {
      t.view.devicePixelRatio = 3;
      t.view.physicalSize = const Size(430 * 3, 932 * 3);
      addTearDown(t.view.reset);
      await t.pumpWidget(ScreenUtilInit(
        designSize: designSize,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light(),
          home: const SplashScreen(hold: true),
        ),
      ));
      final logo = find.byType(RijHubLogo);
      expect(
        find.ancestor(of: logo, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.ancestor(of: logo, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(t.getSize(logo).height, 64);
    });
  });
}
