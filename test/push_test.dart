import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rijhub/app/push.dart';
import 'package:rijhub/data/api/api_client.dart';
import 'package:rijhub/data/api/api_context.dart';
import 'package:rijhub/data/api/api_repositories.dart';
import 'package:rijhub/data/api/realtime.dart';
import 'package:rijhub/data/api/token_store.dart';
import 'package:rijhub/data/api/uploads.dart';

void main() {
  group('push notifications', () {
    test('open only screens inside the app', () {
      expect(appRouteOf({'route': '/booking/b1'}), '/booking/b1');
      expect(appRouteOf({'route': '/account/wallet'}), '/account/wallet');
      expect(appRouteOf({'route': 'https://example.com'}), isNull);
      expect(appRouteOf({'route': '//example.com/x'}), isNull);
      expect(appRouteOf({'route': ''}), isNull);
      expect(appRouteOf({'route': 42}), isNull);
      expect(appRouteOf({}), isNull);
    });

    test('register this phone, and drop it on signing out', () async {
      final calls = <String>[];
      final bodies = <Object?>[];
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'access', refresh: 'refresh');
      final api = ApiClient(
        baseUrl: Uri.parse('http://api.test'),
        tokens: tokens,
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          bodies.add(request.body.isEmpty ? null : jsonDecode(request.body));
          return http.Response('', 204);
        }),
      );
      final auth = ApiAuthRepository(ApiContext(
        api: api,
        uploads: Uploader(api),
        live: Realtime(api),
        checkout: (url, {required callback}) async => false,
      ));

      await auth.registerDevice('fcm-token-123', platform: 'ios');
      expect(auth.deviceToken, 'fcm-token-123');
      await auth.signOut();

      expect(calls, [
        'POST /v1/me/devices',
        'DELETE /v1/me/devices/fcm-token-123',
      ]);
      expect(bodies.first, {'token': 'fcm-token-123', 'platform': 'ios'});
      expect(auth.deviceToken, isNull);
    });
  });
}
