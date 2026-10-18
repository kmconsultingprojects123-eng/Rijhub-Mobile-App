// Runs the real app (router, session, providers) on mock data, the way
// main.dart does, for flow tests. The mocks wait with Future.delayed, so
// tests pump fake time rather than await.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/location.dart';
import 'package:rijhub/app/media.dart';
import 'package:rijhub/app/push.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/geo/places.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/features/auth/auth_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is using the app.
enum As { firstOpen, guestClient, guestArtisan, client, artisan }

class Launched {
  Launched(this.session, this.deps);

  final SessionController session;
  final AppDependencies deps;
}

/// Starts the app as [as], at [at] (the app's own start when null), on a
/// 390 x 844 phone.
/// Notifications count as already allowed unless [pushAllowed] is false,
/// so the one-time offer only shows in the tests about it.
Future<Launched> launch(WidgetTester t,
    {As as = As.client, String? at, bool pushAllowed = true}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  t.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);

  SharedPreferences.setMockInitialValues({
    if (as != As.firstOpen) 'session.onboarded': true,
    if (as == As.guestArtisan) 'session.guestRole': 'artisan',
  });
  final prefs = await SharedPreferences.getInstance();
  final deps = AppDependencies.mock(
    live: false,
    media: SampleMediaService(),
    location: SampleLocationService(AbujaPlaces.centreOf('Gwarinpa')),
    push: SamplePushPermission(allowed: pushAllowed),
  );
  final session = SessionController(prefs: prefs, auth: deps.auth)..restore();
  if (as == As.client) {
    await session.signIn(MockData.sampleUser(UserRole.client));
  }
  if (as == As.artisan) {
    await session.signIn(MockData.sampleUser(UserRole.artisan));
  }
  final authFlow = AuthFlowController(auth: deps.auth, session: session);
  await t.pumpWidget(RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: authFlow,
    authGate: AuthGate(showAuthSheet),
    initialLocation: at,
  ));
  await wait(t);
  return Launched(session, deps);
}

/// Runs [body] in the app, then lets the mocks' last timers finish so the
/// test ends clean.
void appTest(String description, Future<void> Function(WidgetTester t) body) {
  testWidgets(description, (t) async {
    await body(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}

/// Pumps [seconds] of fake time in small steps, so mock delays finish and
/// animations move on without waiting for endless ones (typing dots).
Future<void> wait(WidgetTester t, [double seconds = 2]) async {
  for (var i = 0; i < (seconds * 10).round(); i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the last widget showing [text] (scrolling to it first).
Future<void> tapText(WidgetTester t, String text,
    {double then = 1.5, bool exact = false}) async {
  final f = exact ? find.text(text) : find.textContaining(text);
  expect(f, findsWidgets, reason: 'No "$text" to tap');
  await t.ensureVisible(f.last);
  await t.pump();
  await t.tap(f.last, warnIfMissed: false);
  await wait(t, then);
}

/// Taps the last widget screen readers know as [label].
Future<void> tapLabel(WidgetTester t, String label, {double then = 1.5}) async {
  final f = find.bySemanticsLabel(label);
  expect(f, findsWidgets, reason: 'Nothing labelled "$label"');
  await t.tap(f.last, warnIfMissed: false);
  await wait(t, then);
}

/// Goes to [location] as a link would.
Future<void> go(WidgetTester t, String location, {double then = 2}) async {
  GoRouter.of(t.element(find.byType(Scaffold).first)).go(location);
  await wait(t, then);
}

/// The quick replies and chips in view that are picked.
Finder get pickedChips =>
    find.byWidgetPredicate((w) => w is PromptChip && w.selected);
