import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
///     {"route": "/home", "role": "client", "phone": "7000000100",
///      "code": "123456", "verify": true}                      signed in for
///                                                             real (the API)
///
/// Add `"step": "details"` to open the sheet on the details step, or
/// `"channel": "whatsapp"` for a code sent on WhatsApp. `"ask": "AC not
/// cooling"` opens the Ask conversation with that problem said, and
/// `"askScript": ["Book Emeka", "Tomorrow", "12 Aminu Kano Crescent, Wuse 2"]`
/// then answers it, one reply or typed line per step; `"askVoice": true`
/// opens it recording a voice note, as the home's microphone does. `"send": true`
/// asks for a real code, as the phone step does (then checks [code] with
/// `"verify": true`); `"firebaseTestNumbers": true` lets Firebase's test
/// numbers, which have fixed codes and get no text, sign in on a simulator, and
/// `"forceRecaptcha": true` sends real texts from an emulator. iOS hides
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
    this.ask,
    this.askScript = const [],
    this.askVoice = false,
    this.verify = false,
    this.channel = OtpChannel.sms,
    this.send = false,
    this.firebaseTestNumbers = false,
    this.forceRecaptcha = false,
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

  /// A problem to open the Ask conversation with, as if typed.
  final String? ask;

  /// Answers to play through that conversation (AskLaunch.script).
  final List<String> askScript;

  /// Opens the Ask conversation recording a voice note.
  final bool askVoice;

  /// Signs in with [phone] and [code] through the real sign-in: with the
  /// API, the code is one it sent (read from its log in development).
  final bool verify;

  /// How the code at the code step was sent.
  final OtpChannel channel;

  /// Asks for a real code instead of pretending one was sent.
  final bool send;

  /// Skips Firebase's human check, which only its test numbers allow.
  final bool firebaseTestNumbers;

  /// Sends real texts from a build not installed from Google Play (an
  /// emulator, say), through Firebase's web check instead of Play's.
  final bool forceRecaptcha;

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
        ask: json['ask'] as String?,
        askScript: [for (final s in json['askScript'] as List? ?? []) '$s'],
        askVoice: json['askVoice'] == true,
        verify: json['verify'] == true,
        send: json['send'] == true,
        firebaseTestNumbers: json['firebaseTestNumbers'] == true,
        forceRecaptcha: json['forceRecaptcha'] == true,
        channel: json['channel'] == 'whatsapp'
            ? OtpChannel.whatsapp
            : OtpChannel.sms,
      );
    } on Object {
      return const DevLaunch();
    }
  }

  /// Puts the session and the sign-in flow into the requested state.
  Future<void> apply(SessionController session, AuthFlowController flow) async {
    if (!active) return;
    // Already signed in as that number: the session is kept, so a run of
    // captures signs in once (Firebase throttles repeated phone sign-ins).
    final again = phone != null &&
        send &&
        session.isSignedIn &&
        session.user?.phone == NigerianPhone.toE164(phone!);
    // Every QA launch that sets a screen up starts clean, so one capture
    // never inherits another's state (an area picked in the last one, say).
    // Firebase's test numbers alone keep whoever is signed in.
    final setsUp = route != null ||
        role != null ||
        signedIn ||
        phone != null ||
        area != null ||
        sheet != null ||
        signInPrompt != null;
    if (setsUp && !again) {
      // Signing in as someone else ends the last account's server session
      // too: reset() alone keeps its tokens, and the API would still answer
      // as them.
      if (phone != null && send) await session.signOut();
      await session.reset();
    }
    final firstLaunch = role == null ||
        route == Routes.welcome ||
        (route ?? '').startsWith(Routes.splash);
    if (again) {
      // Signed in already: nothing to set up.
    } else if (signedIn) {
      await session.signIn(MockData.sampleUser(role ?? UserRole.client));
    } else if (!firstLaunch) {
      await session.continueAsGuest(role!);
    }
    if (firebaseTestNumbers && Firebase.apps.isNotEmpty) {
      await FirebaseAuth.instance
          .setSettings(appVerificationDisabledForTesting: true);
    }
    if (forceRecaptcha && Firebase.apps.isNotEmpty) {
      await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
    }
    if (phone != null && send && !again) {
      try {
        final done = await flow.sendCode(phone!, channel: channel);
        if (done == null && verify && code != null) await flow.verify(code!);
      } on Object catch (e) {
        debugPrint('dev launch: sign-in failed: $e');
      }
    } else if (phone != null && !send) {
      flow.restoreChallenge(
        phone!,
        OtpChallenge(
          phone: NigerianPhone.toE164(phone!),
          channel: channel,
          requestId: 'dev',
          resendAvailableAt: DateTime.now().add(const Duration(seconds: 24)),
        ),
      );
      flow.draftCode = code ?? '';
      flow.needsDetails = detailsStep;
      if (verify && code != null) {
        try {
          await flow.verify(code!);
        } on Object catch (e) {
          debugPrint('dev launch: sign-in failed: $e');
        }
      }
    }
    if (area != null) await session.setArea(area!);
  }
}
