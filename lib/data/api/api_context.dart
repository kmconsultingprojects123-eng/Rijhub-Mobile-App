import 'dart:async';

import '../repositories/repositories.dart';
import 'api_client.dart';
import 'api_codec.dart';
import 'realtime.dart';
import 'uploads.dart';

/// Opens the payment partner's checkout at [url]; true once it came back
/// to [callback].
typedef Checkout = Future<bool> Function(Uri url, {required Uri callback});

/// What every API repository shares: the client, uploads, the live
/// connection, the checkout, and a signal for "something changed, look
/// again" (a chat thread, the unread counts), fed by live events and the
/// person's own actions.
class ApiContext {
  ApiContext({
    required this.api,
    required this.uploads,
    required this.live,
    required this.checkout,
  }) {
    live.events.listen((event) {
      switch (event['type']) {
        case 'message' || 'read':
          changed(event['conversation_id'] as String? ?? '');
          changed(unreadMessages);
        case 'notification':
          changed(notices);
      }
    });
  }

  /// [changed] keys besides conversation ids.
  static const unreadMessages = 'unread-messages';
  static const notices = 'notices';

  /// Everything: after signing in or out.
  static const everything = '*';

  final ApiClient api;
  final Uploader uploads;
  final Realtime live;
  final Checkout checkout;
  final _changes = StreamController<String>.broadcast();

  void changed(String what) => _changes.add(what);

  /// Fires for [what] (and for [everything]).
  Stream<void> changes(String what) =>
      _changes.stream.where((c) => c == what || c == everything);

  Future<bool> get signedIn => api.signedIn;

  /// [run] for a signed-in person; [guest] for anyone else, without asking
  /// the API (which would only say "sign in").
  Future<T> forMember<T>(Future<T> Function() run, T guest) async {
    if (!await signedIn) return guest;
    return run();
  }

  /// A list that stays current: loaded when someone listens, again on each
  /// of [what]'s changes, and every [poll] while the live connection is
  /// down. A failed reload keeps what was shown; only a first load that
  /// fails reports the error.
  Stream<T> watching<T>(String what, Future<T> Function() load,
      {Duration poll = const Duration(seconds: 20)}) {
    late final StreamController<T> out;
    StreamSubscription<void>? changes;
    Timer? timer;
    var loaded = false;
    var busy = false;
    var again = false;
    Future<void> reload() async {
      if (busy) {
        again = true;
        return;
      }
      busy = true;
      try {
        final value = await load();
        loaded = true;
        if (!out.isClosed) out.add(value);
      } on Object catch (e, stack) {
        if (!loaded && !out.isClosed) out.addError(e, stack);
      } finally {
        busy = false;
        if (again) {
          again = false;
          unawaited(reload());
        }
      }
    }

    out = StreamController<T>(
      onListen: () {
        unawaited(reload());
        changes = this.changes(what).listen((_) => reload());
        timer = Timer.periodic(poll, (_) {
          if (!live.connected) unawaited(reload());
        });
      },
      onCancel: () {
        changes?.cancel();
        timer?.cancel();
      },
    );
    return out.stream;
  }

  /// Money taken on the payment partner's checkout, then checked: [created]
  /// is the API's `{booking, payment}`. Without Paystack keys (local
  /// development) the API is in test mode and nothing opens.
  Future<Json> pay(Json created) async {
    final booking = asMap(created['booking']);
    final payment = asMap(created['payment']);
    final id = booking['id']! as String;
    var closed = false;
    if (payment['test_mode'] != true) {
      final url = payment['authorization_url'] as String?;
      if (url == null) {
        throw const AppException(
            "We couldn't start the payment. Try again in a moment.");
      }
      final callback = Uri.parse(payment['callback_url'] as String? ??
          'https://rijhub.com/payment/callback');
      closed = !await checkout(Uri.parse(url), callback: callback);
    }
    try {
      // Checked even when the checkout was closed: a transfer or USSD
      // payment can finish without the page coming back.
      return asMap(await api.post('/v1/bookings/$id/payment/verify'));
    } on ApiException catch (e) {
      if (e.code == 'not_paid' && closed) {
        throw const AppException('Payment cancelled. Nothing was taken.');
      }
      rethrow;
    }
  }
}
