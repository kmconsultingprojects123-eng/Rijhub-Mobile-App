import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/auth_gate.dart';
import 'app/dependencies.dart';
import 'app/dev_launch.dart';
import 'app/session.dart';
import 'features/auth/auth_sheet.dart';
import 'features/location/area_picker_sheet.dart';
import 'firebase_options.dart';

/// Entry point for the redesigned app.
///
/// With an API address it talks to the RijHub API:
///
///     flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
///
/// Without one it runs on the sample data in `lib/data/mock/`. The previous
/// app is kept for reference in `lib/legacy/` and still runs with
/// `flutter run -t lib/legacy/main.dart`.
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone layouts are designed for portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Push notifications need Firebase; only the app on the API uses it.
  if (_apiBaseUrl.isNotEmpty) await _startFirebase();

  final prefs = await SharedPreferences.getInstance();
  final navigatorKey = GlobalKey<NavigatorState>();
  final dependencies = _apiBaseUrl.isEmpty
      ? AppDependencies.mock()
      : AppDependencies.api(baseUrl: Uri.parse(_apiBaseUrl), navigator: navigatorKey);
  final session = SessionController(prefs: prefs, auth: dependencies.auth)
    ..restore();
  // A saved sign-in without its session (the app was reinstalled, or last
  // ran on sample data) is signed out rather than half signed in.
  if (session.isSignedIn && !await dependencies.hasSession()) {
    await session.signOut();
  }
  // The server ended the session: signed out on every device, or the
  // account was deleted or suspended.
  dependencies.sessionEnded.listen((_) => session.signOut());
  final authFlow = AuthFlowController(
    auth: dependencies.auth,
    session: session,
  );

  final dev = await DevLaunch.load();
  await dev.apply(session, authFlow);

  unawaited(dependencies.startPush());
  runApp(RijHubApp(
    dependencies: dependencies,
    session: session,
    authFlow: authFlow,
    authGate: AuthGate(showAuthSheet),
    initialLocation: dev.route,
    navigatorKey: navigatorKey,
    debugSignInPrompt: dev.signInPrompt,
    debugOnLaunch: dev.sheet == 'area'
        ? (context) async {
            final area = await showAreaPicker(context, current: session.area);
            if (area != null) await session.setArea(area);
          }
        : null,
  ));
}

Future<void> _startFirebase() async {
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } on Object {
    // The app works without it; it just gets no push notifications.
  }
}
