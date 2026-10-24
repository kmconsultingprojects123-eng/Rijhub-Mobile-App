import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/data/api/api_client.dart';
import 'package:rijhub/data/api/api_context.dart';
import 'package:rijhub/data/api/api_repositories.dart';
import 'package:rijhub/data/api/phone_verifier.dart';
import 'package:rijhub/data/api/realtime.dart';
import 'package:rijhub/data/api/token_store.dart';
import 'package:rijhub/data/api/uploads.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for Firebase: a text named 'v-1' whose code is 123456, or, with
/// [instant], a number the phone confirms by itself. [read] completes when
/// the phone reads the code in the text by itself, as Android does.
class _FakePhone implements PhoneVerifier {
  _FakePhone({this.instant = false});

  final bool instant;
  final read = Completer<String>();
  int confirms = 0;

  @override
  Future<PhoneVerification> send(String phone) async => instant
      ? const PhoneVerification.verified('proof-instant')
      : PhoneVerification.codeSent('v-1', readByPhone: read.future);

  @override
  Future<String> confirm(String verificationId, String code) async {
    confirms++;
    if (verificationId != 'v-1' || code != '123456') {
      throw const AuthException("That code isn't right. Check the text.");
    }
    return 'proof-1';
  }
}

/// An API that leaves texting to the app, and calls every number new.
class _Api {
  _Api(PhoneVerifier phone) {
    final api = ApiClient(
      baseUrl: Uri.parse('http://api.test'),
      tokens: MemoryTokenStore(),
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        bodies.add(request.body.isEmpty ? null : jsonDecode(request.body));
        final body = switch (request.url.path) {
          '/v1/auth/otp' => {
              'phone': '+2348031234567',
              'channel': 'sms',
              'via': 'firebase',
              'resend_at': '2030-01-01T00:00:00Z',
              'expires_in': 600,
              'message': "We'll text a 6-digit code.",
            },
          '/v1/auth/firebase' => {'status': 'new', 'signup_token': 'signup-1'},
          _ => <String, Object?>{},
        };
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    auth = ApiAuthRepository(
      ApiContext(
        api: api,
        uploads: Uploader(api),
        live: Realtime(api),
        checkout: (url, {required callback}) async => false,
      ),
      phone: phone,
    );
  }

  late final ApiAuthRepository auth;
  final calls = <String>[];
  final bodies = <Object?>[];
}

void main() {
  group('codes texted through Firebase', () {
    test('a typed code becomes proof the API checks', () async {
      final api = _Api(_FakePhone());
      final sent = await api.auth.requestCode('+2348031234567');
      expect(sent.channel, OtpChannel.sms);
      expect(sent.verified, isFalse);

      final result = await api.auth.verifyCode(sent, '123456');
      expect(result.isNewUser, isTrue);
      expect(api.calls, ['POST /v1/auth/otp', 'POST /v1/auth/firebase']);
      expect(api.bodies.last, {'id_token': 'proof-1'});
    });

    test('a wrong code says so, without asking the API', () async {
      final api = _Api(_FakePhone());
      final sent = await api.auth.requestCode('+2348031234567');
      await expectLater(
        api.auth.verifyCode(sent, '000000'),
        throwsA(isA<AuthException>().having(
            (e) => e.message, 'message', startsWith("That code isn't right"))),
      );
      expect(api.calls, ['POST /v1/auth/otp']);
    });

    test('a number the phone confirmed needs no code, once', () async {
      final api = _Api(_FakePhone(instant: true));
      final sent = await api.auth.requestCode('+2348031234567');
      expect(sent.verified, isTrue);

      expect((await api.auth.verifyCode(sent, '')).isNewUser, isTrue);
      expect(api.bodies.last, {'id_token': 'proof-instant'});
      await expectLater(
          api.auth.verifyCode(sent, ''), throwsA(isA<AuthException>()));
    });

    test('a code the phone reads from the text needs no typing', () async {
      SharedPreferences.setMockInitialValues({});
      final phone = _FakePhone();
      final api = _Api(phone);
      final session = SessionController(
          prefs: await SharedPreferences.getInstance(), auth: api.auth);
      final flow = AuthFlowController(auth: api.auth, session: session);
      final read = <bool>[];
      flow.readByPhone.listen(read.add);

      // The text is on its way: a code to type, for now.
      expect(await flow.sendCode('8031234567'), isNull);
      expect(flow.needsDetails, isFalse);

      // It lands, and Android reads its code.
      phone.read.complete('proof-read');
      await pumpEventQueue();

      expect(read, [false]);
      expect(flow.needsDetails, isTrue);
      expect(api.bodies.last, {'id_token': 'proof-read'});
      expect(phone.confirms, 0);
    });

    test('a code typed first is checked once, even if the phone reads it too',
        () async {
      SharedPreferences.setMockInitialValues({});
      final phone = _FakePhone();
      final api = _Api(phone);
      final session = SessionController(
          prefs: await SharedPreferences.getInstance(), auth: api.auth);
      final flow = AuthFlowController(auth: api.auth, session: session);
      final read = <bool>[];
      flow.readByPhone.listen(read.add);

      await flow.sendCode('8031234567');
      expect(await flow.verify('123456'), isFalse);
      phone.read.complete('proof-read');
      await pumpEventQueue();

      expect(read, isEmpty);
      expect(
          api.calls.where((c) => c == 'POST /v1/auth/firebase'), hasLength(1));
    });

    test('a new number the phone confirmed goes straight to its details',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = _Api(_FakePhone(instant: true));
      final session = SessionController(
          prefs: await SharedPreferences.getInstance(), auth: api.auth);
      final flow = AuthFlowController(auth: api.auth, session: session);

      expect(await flow.sendCode('8031234567'), isFalse);
      expect(flow.needsDetails, isTrue);
      expect(session.isSignedIn, isFalse);
    });
  });
}
