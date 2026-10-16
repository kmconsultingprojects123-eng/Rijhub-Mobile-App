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

/// Entry point for the redesigned app.
///
/// It talks to no backend: data comes from `lib/data/mock/`. Firebase, push
/// notifications and the real API are wired in once the new backend exists.
/// The previous app is kept for reference in `lib/legacy/` and still runs
/// with `flutter run -t lib/legacy/main.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone layouts are designed for portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final dependencies = AppDependencies.mock();
  final session = SessionController(prefs: prefs, auth: dependencies.auth)
    ..restore();
  final authFlow = AuthFlowController(
    auth: dependencies.auth,
    session: session,
  );

  final dev = await DevLaunch.load();
  await dev.apply(session, authFlow);

  runApp(RijHubApp(
    dependencies: dependencies,
    session: session,
    authFlow: authFlow,
    authGate: AuthGate(showAuthSheet),
    initialLocation: dev.route,
    debugSignInPrompt: dev.signInPrompt,
    debugOnLaunch: dev.sheet == 'area'
        ? (context) async {
            final area = await showAreaPicker(context, current: session.area);
            if (area != null) await session.setArea(area);
          }
        : null,
  ));
}
