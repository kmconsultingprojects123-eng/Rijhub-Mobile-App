import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/formatters.dart';
import '../data/mock/mock_data.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import 'auth_gate.dart';
import 'routes.dart';
import 'session.dart';

/// Debug-only launch options for screenshots and QA.
///
/// Write `Documents/dev_launch.json` into the app's container, then launch:
///
///     {"route": "/welcome"}                                   first launch
///     {"route": "/home", "role": "client"}                    guest client
///     {"route": "/home", "role": "client", "area": "Gwarinpa",
///      "sheet": "area"}                                       area picker
///     {"route": "/home", "role": "artisan", "signedIn": true} signed-in artisan
///     {"route": "/home", "role": "client", "signIn": "postJob",
///      "phone": "8031234567", "code": "4829"}                 sheet, code step
///
/// Add `"step": "details"` to open the sheet on the details step. iOS hides
/// environment variables from Dart, so a file is the dependable channel on
/// the simulator. Release builds never read it.
class DevLaunch {
  const DevLaunch({
    this.active = false,
    this.route,
    this.signedIn = false,
    this.role,
    this.phone,
    this.code,
    this.signInPrompt,
    this.detailsStep = false,
    this.area,
    this.sheet,
  });

  final bool active;
  final String? route;
  final bool signedIn;
  final UserRole? role;
  final String? phone;
  final String? code;

  /// Opens the sign-in sheet with this prompt after the first frame.
  final AuthPrompt? signInPrompt;
  final bool detailsStep;

  /// The area to browse, as if picked.
  final String? area;

  /// A sheet to open after the first frame: "area" for the area picker.
  final String? sheet;

  static Future<DevLaunch> load() async {
    if (!kDebugMode || kIsWeb) return const DevLaunch();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/dev_launch.json');
      if (!file.existsSync()) return const DevLaunch();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      if (json.isEmpty) return const DevLaunch();
      final role = json['role'] as String?;
      return DevLaunch(
        active: true,
        route: json['route'] as String?,
        signedIn: json['signedIn'] == true,
        role: role == null ? null : UserRole.values.byName(role),
        phone: json['phone'] as String?,
        code: json['code'] as String?,
        signInPrompt: AuthPrompt.byName[json['signIn']],
        detailsStep: json['step'] == 'details',
        area: json['area'] as String?,
        sheet: json['sheet'] as String?,
      );
    } on Object {
      return const DevLaunch();
    }
  }

  /// Puts the session and the sign-in flow into the requested state.
  Future<void> apply(SessionController session, AuthFlowController flow) async {
    if (!active) return;
    // Every QA launch starts clean, so one capture never inherits another's
    // state (an area picked in the last one, say).
    await session.reset();
    final firstLaunch = role == null ||
        route == Routes.welcome ||
        (route ?? '').startsWith(Routes.splash);
    if (signedIn) {
      await session.signIn(MockData.sampleUser(role ?? UserRole.client));
    } else if (!firstLaunch) {
      await session.continueAsGuest(role!);
    }
    if (phone != null) {
      flow.restoreChallenge(
        phone!,
        OtpChallenge(
          phone: NigerianPhone.toE164(phone!),
          channel: OtpChannel.sms,
          requestId: 'dev',
          resendAvailableAt: DateTime.now().add(const Duration(seconds: 24)),
        ),
      );
      flow.draftCode = code ?? '';
      flow.needsDetails = detailsStep;
    }
    if (area != null) await session.setArea(area!);
  }
}
