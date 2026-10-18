import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rijhub/data/api/api_client.dart';
import 'package:rijhub/data/api/api_codec.dart';
import 'package:rijhub/data/api/token_store.dart';
import 'package:rijhub/data/models/models.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<ApiClient> _client(
  Future<http.Response> Function(http.Request request) handler, {
  bool signedIn = true,
}) async {
  final tokens = MemoryTokenStore();
  if (signedIn) await tokens.save(access: 'old-access', refresh: 'refresh-1');
  return ApiClient(
    baseUrl: Uri.parse('http://api.test'),
    tokens: tokens,
    client: MockClient(handler),
  );
}

void main() {
  group('the API client', () {
    test('sends the token and reads JSON back', () async {
      late http.Request seen;
      final api = await _client((r) async {
        seen = r;
        return _json(200, {'ok': true});
      });
      expect(await api.get('/v1/me', query: {'area': 'Wuse 2', 'skip': null}),
          {'ok': true});
      expect(seen.headers['Authorization'], 'Bearer old-access');
      expect(seen.url.toString(), 'http://api.test/v1/me?area=Wuse+2');
    });

    test("turns the API's errors into messages people can read", () async {
      final api = await _client((_) async => _json(409, {
            'detail': {
              'code': 'already_quoted',
              'message': "You've already quoted on this job."
            }
          }));
      await expectLater(
        api.post('/v1/jobs/1/quotes', {'price': 1}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'already_quoted')
            .having((e) => e.message, 'message',
                "You've already quoted on this job.")),
      );
    });

    test('a request that never reaches RijHub says so', () async {
      final api =
          await _client((_) async => throw const SocketException('no route'));
      await expectLater(
          api.get('/v1/me'),
          throwsA(
              isA<ApiException>().having((e) => e.offline, 'offline', isTrue)));
    });

    test(
        'an expired token is refreshed once, even for requests at the same time',
        () async {
      var refreshes = 0;
      final api = await _client((r) async {
        if (r.url.path == '/v1/auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json(200,
              {'access_token': 'new-access', 'refresh_token': 'refresh-2'});
        }
        if (r.headers['Authorization'] == 'Bearer old-access') {
          return _json(401, {
            'detail': {'code': 'token_expired', 'message': 'Sign in again.'}
          });
        }
        return _json(200, {'path': r.url.path});
      });
      final results = await Future.wait(
          [api.get('/v1/a'), api.get('/v1/b'), api.get('/v1/c')]);
      expect(results, [
        {'path': '/v1/a'},
        {'path': '/v1/b'},
        {'path': '/v1/c'},
      ]);
      expect(refreshes, 1);
      expect(await api.tokens.access(), 'new-access');
    });

    test('a session the server ended signs the device out', () async {
      final api = await _client((r) async => r.url.path == '/v1/auth/refresh'
          ? _json(401, {
              'detail': {
                'code': 'session_ended',
                'message': 'You were signed out.'
              }
            })
          : _json(401, {
              'detail': {
                'code': 'session_ended',
                'message': 'You were signed out.'
              }
            }));
      final ended = api.sessionEnded.first;
      await expectLater(api.get('/v1/me'), throwsA(isA<ApiException>()));
      await ended.timeout(const Duration(seconds: 1));
      expect(await api.tokens.access(), isNull);
    });

    test(
        'a refresh that fails for want of a connection keeps the person signed in',
        () async {
      final api = await _client((r) async {
        if (r.url.path == '/v1/auth/refresh') {
          throw const SocketException('offline');
        }
        return _json(401, {
          'detail': {'code': 'token_expired', 'message': 'Sign in again.'}
        });
      });
      var ended = false;
      api.sessionEnded.listen((_) => ended = true);
      await expectLater(
          api.get('/v1/me'),
          throwsA(
              isA<ApiException>().having((e) => e.offline, 'offline', isTrue)));
      expect(ended, isFalse);
      expect(await api.tokens.access(), 'old-access');
    });

    test('a suspended account is signed out', () async {
      final api = await _client((_) async => _json(403, {
            'detail': {
              'code': 'account_suspended',
              'message': 'This account has been suspended.'
            }
          }));
      await expectLater(api.get('/v1/me'), throwsA(isA<ApiException>()));
      expect(await api.tokens.access(), isNull);
    });

    test("a guest's requests carry no token, and a 401 doesn't end anything",
        () async {
      late http.Request seen;
      final api = await _client((r) async {
        seen = r;
        return _json(401, {
          'detail': {'code': 'not_signed_in', 'message': 'Sign in to do that.'}
        });
      }, signedIn: false);
      var ended = false;
      api.sessionEnded.listen((_) => ended = true);
      await expectLater(
          api.get('/v1/me'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'not_signed_in')));
      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(ended, isFalse);
    });
  });

  group('the mapping', () {
    test('times arrive as local and leave as UTC', () {
      final booking = bookingFrom(asMap(jsonDecode('''{
        "id": "b1", "ref": "RJH-1", "service_name": "AC servicing", "category_id": "ac",
        "scheduled_at": "2026-10-19T09:00:00Z",
        "window": {"start": "2026-10-19T09:00:00Z", "end": "2026-10-19T11:00:00Z"},
        "status": "on_the_way", "counterpart_id": "a1", "counterpart_name": "Emeka Nwosu",
        "area": "Wuse 2", "artisan_id": "a1", "price": 8000, "fee": 400, "total": 8400,
        "payment": "held", "photos": [], "created_at": "2026-10-18T09:00:00Z"
      }''')));
      expect(booking.scheduledAt.isUtc, isFalse);
      expect(booking.scheduledAt.toUtc(), DateTime.utc(2026, 10, 19, 9)); // the same moment
      expect(booking.status, BookingStatus.onTheWay);
      expect(booking.payment, PaymentState.held);
      expect(booking.total, 8400);
      expect(iso(DateTime.utc(2026, 10, 19, 9)), '2026-10-19T09:00:00.000Z');
    });

    test("listed services go by id, anything else by name and price", () {
      const listed = ServiceOffer(
          id: 'svc1', categoryId: 'ac', name: 'AC servicing', price: 8000);
      const asked = ServiceOffer(
          id: 'ask_a1', categoryId: 'ac', name: 'Gas top-up', price: 12000);
      const both = ServiceOffer(
          id: 'multi_svc1',
          categoryId: 'ac',
          name: 'AC servicing + Gas top-up',
          price: 20000,
          parts: [listed, asked]);
      expect(bookedServices(listed), [
        {'service_id': 'svc1'}
      ]);
      expect(bookedServices(both), [
        {'service_id': 'svc1'},
        {'name': 'Gas top-up', 'category_id': 'ac', 'price': 12000},
      ]);
    });

    test('an artisan with no distance or location still reads', () {
      final a = artisanFrom(asMap(jsonDecode('''{
        "id": "a1", "name": "Emeka Nwosu", "trade": "AC technician", "category_id": "ac",
        "area": "Wuse 2", "rating": 4.9, "review_count": 128, "jobs_completed": 214,
        "starting_price": 5000, "is_verified": true, "is_available_today": true
      }''')));
      expect(a.distanceKm, 0);
      expect(a.location, isNull);
      expect(a.isVerified, isTrue);
    });
  });
}
