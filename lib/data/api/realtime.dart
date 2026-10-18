import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'api_codec.dart';

/// The one live connection an open app keeps (`/v1/ws`): new messages,
/// read receipts and notifications the moment they happen. It pings every
/// 25 seconds, comes back by itself after a drop (with a growing pause),
/// and when the server closes it because the session ended (code 4401) it
/// refreshes the token and reconnects, or signs out if that's refused.
class Realtime {
  Realtime(this._api);

  final ApiClient _api;
  final _events = StreamController<Json>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _ping;
  Timer? _retry;
  bool _wanted = false;
  bool _connecting = false;
  int _failures = 0;

  /// Each event: `{"type": "message" | "read" | "notification", …}`.
  Stream<Json> get events => _events.stream;

  /// Connected right now. Screens that need fresh data poll less often
  /// while it is.
  bool get connected => _channel != null;

  /// Starts (or keeps) the connection for the signed-in person.
  void start() {
    _wanted = true;
    _connect();
  }

  /// Closes it, for signing out.
  void stop() {
    _wanted = false;
    _retry?.cancel();
    _close();
  }

  Future<void> _connect() async {
    if (!_wanted || _channel != null || _connecting) return;
    _connecting = true;
    try {
      final token = await _api.tokens.access();
      if (token == null) return;
      final base = _api.baseUrl;
      final uri = _api.url('/v1/ws', {'token': token}).replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
      );
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (!_wanted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _failures = 0;
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onClosed(channel),
        onError: (Object _) => _onClosed(channel),
      );
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          channel.sink.add('ping');
        } on Object {
          // Closing: onDone handles it.
        }
      });
    } on Object catch (e) {
      debugPrint('realtime: connect failed: $e');
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _onData(Object? data) {
    if (data is! String || data == 'pong') return;
    try {
      final event = jsonDecode(data);
      if (event is Map) _events.add(event.cast<String, Object?>());
    } on FormatException {
      // Not an event.
    }
  }

  Future<void> _onClosed(WebSocketChannel channel) async {
    if (!identical(channel, _channel)) return;
    final code = channel.closeCode;
    _close();
    if (!_wanted) return;
    if (code == 4401) {
      // The token ran out or the session ended: try a fresh token.
      final refreshed = await _api.refreshTokens();
      if (refreshed == false) {
        await _api.endSession();
        return;
      }
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _retry?.cancel();
    _failures++;
    final seconds = math.min(30, 1 << math.min(_failures, 5));
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  void _close() {
    _ping?.cancel();
    _ping = null;
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    channel?.sink.close();
  }
}
