import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../state/app_state_notifier.dart';
import '../api_config.dart';
import '../services/token_storage.dart';

// Allow optional socket path override via dart-define: --dart-define=SOCKET_PATH=/socket.io
const _socketPathKey = 'SOCKET_PATH';
final String SOCKET_PATH = const String.fromEnvironment(_socketPathKey);

/// Re-introduces socket.io-based realtime notifications with controlled debug-only logging
/// and improved error handling; preserves public API (instance/init/connect/disconnect).
class RealtimeNotifications {
  static RealtimeNotifications? _instance;
  static RealtimeNotifications get instance => _instance ??= RealtimeNotifications._();

  io.Socket? _socket;
  // Broadcast stream for incoming realtime events (chat/message/thread events)
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  /// Whether the underlying socket is connected.
  bool get connected => _socket != null && _socket!.connected;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  bool _connecting = false;

  RealtimeNotifications._();

  // Internal logger: only logs in debug builds to avoid noisy production logs.
  void _log(String msg) {
    if (kDebugMode) debugPrint('RealtimeNotifications: $msg');
  }

  /// Initialize the notifications subsystem.
  Future<void> init() async {
    if (initialized || _connecting) return;
    _connecting = true;
    try {
      _log('RealtimeNotifications: init');
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        _log('RealtimeNotifications: no token');
        _connecting = false;
        return;
      }

      // Initialize local notifications (silently, errors ignored)
      try {
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        const ios = DarwinInitializationSettings();
        const initSettings = InitializationSettings(android: android, iOS: ios);
        await _local.initialize(initSettings, onDidReceiveNotificationResponse: (payload) async {
          try {
            if (payload.payload != null) {
              // optional: handle taps
            }
          } catch (_) {}
        });
      } catch (e) {
        _log('local notification init failed: $e');
      }

      initialized = true;

      // Attempt to connect if token available
      try {
        connect(token);
      } catch (e) {
        _log('init token check failed: $e');
      }

      // React to auth changes
      AppStateNotifier.instance.addListener(() async {
        try {
          final t = AppStateNotifier.instance.token;
          if (t != null && t.isNotEmpty) {
            if (_socket == null || !_socket!.connected) connect(t);
          } else {
            await disconnect();
          }
        } catch (e) {
          _log('auth-change listener failed: $e');
        }
      });
    } finally {
      _connecting = false;
    }
  }

  /// Connect using [token].
  void connect(String token) {
    // print('working');
    // print(token);
    if (token.isEmpty) return;
    if (_connecting) return;
    _connecting = true;

    try {
      // If already connected, keep it; otherwise recreate
      if (_socket != null) {
        try {
          if (_socket!.connected) {
            _log('already connected');
            _connecting = false;
            return;
          }
          _socket!.disconnect();
        } catch (_) {}
        _socket = null;
      }

      final uri = Uri.parse(API_BASE_URL);
      final port = (uri.hasPort && uri.port != 0) ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socketUrl = '${uri.scheme}://${uri.host}:$port';
      _log('connecting to $socketUrl');

      // Log a masked preview of the token for debugging (don't print full token)
      try {
        final tlen = token.length;
        final preview = tlen > 12 ? '${token.substring(0,6)}...${token.substring(tlen-6)}' : token;
        _log('connecting to $socketUrl using token(len=$tlen, preview=$preview)');
      } catch (_) {
        _log('connecting to $socketUrl (token preview unavailable)');
      }

      // Build options: prefer handshake auth, include query fallback, do NOT force websocket-only transport
      final options = <String, dynamic>{
        // Do not force 'websocket' transport: allow polling->upgrade if proxy requires it.
        'autoConnect': false,
        'auth': {'token': token},
        // Some server implementations expect token as a query parameter in the URL (legacy configs).
        'query': {'token': token},
        'timeout': 20000,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 2000,
        'reconnectionDelayMax': 10000,
        'randomizationFactor': 0.5,
      };

      // If a specific socket path is provided via dart-define, include it
      if (SOCKET_PATH.isNotEmpty) options['path'] = SOCKET_PATH;

      _log('socket options: auth present, query token included${SOCKET_PATH.isNotEmpty ? ', path=$SOCKET_PATH' : ''}');
      _socket = io.io(socketUrl, options);

      _socket!.onConnect((_) {
        try {
          final profile = AppStateNotifier.instance.profile;
          final myId = (profile?['_id'] ?? profile?['id'] ?? profile?['userId'])?.toString();
          if (myId != null && myId.isNotEmpty) {
            // Attempt to join a per-user room using a documented-friendly payload.
            try {
              _socket!.emit('join', {'userId': myId});
              // Also emit a legacy 'room' join as a broad fallback for servers that expect that key
              _socket!.emit('join', {'room': myId});
            } catch (_) {}
          }
        } catch (_) {}
        try { _log('socket connected id=${_socket?.id}'); } catch (_) { _log('socket connected'); }
        _connecting = false;
      });

      _socket!.onConnectError((err) {
        try {
          final s = err is String ? err : jsonEncode(err);
          _log('connect error (full): $s');
        } catch (_) {
          _log('connect error: $err');
        }
        _connecting = false;
      });

      _socket!.on('connect_error', (err) {
        try {
          final s = err is String ? err : jsonEncode(err);
          _log('connect_error event (full): $s');
        } catch (_) {
          _log('connect_error event: $err');
        }
      });

      _socket!.on('connect_timeout', (err) {
        _log('connect_timeout event');
      });

      _socket!.onError((err) {
        try {
          final s = err is String ? err : jsonEncode(err);
          _log('socket error (full): $s');
        } catch (_) {
          _log('socket error: $err');
        }
      });

      _socket!.onReconnect((attempt) {
        _log('reconnected after $attempt attempts');
      });

      _socket!.onReconnectAttempt((attempt) {
        _log('reconnect attempt $attempt');
      });
      _socket!.on('reconnect_failed', (err) {
        _log('reconnect_failed: $err');
      });
      _socket!.on('reconnect_error', (err) {
        _log('reconnect_error: $err');
      });

      _socket!.on('notification', (data) async {
        try {
          final payload = data is String ? jsonDecode(data) : (data ?? {});

          // Update unread count if targeted
          try {
            final profile = AppStateNotifier.instance.profile;
            final myId = (profile?['_id'] ?? profile?['id'] ?? profile?['userId'])?.toString();
            String? targetId;
            if (payload is Map) {
              final v = payload['userId'] ?? payload['recipientId'] ?? payload['to'];
              targetId = v != null ? v.toString() : null;
            }
            if (myId?.isNotEmpty ?? false) {
              if (targetId == null || targetId == myId || (payload is Map && payload['broadcast'] == true)) {
                final current = AppStateNotifier.instance.unreadNotifications;
                AppStateNotifier.instance.setUnreadNotifications(current + 1);
              }
            }
          } catch (_) {}

          await _showLocalNotification(payload);
        } catch (e) {
          _log('failed to handle notification: $e');
        }
      });

      // Chat-related events: unify a few server events to the events stream.
      void _forwardEvent(String evName, dynamic data) {
        try {
          final payload = data is String ? jsonDecode(data) : (data ?? {});
          final out = <String, dynamic>{'event': evName};
          if (payload is Map) {
            // Normalize keys to String to satisfy Map<String, dynamic>
            final normalized = <String, dynamic>{};
            payload.forEach((k, v) {
              try {
                normalized[k?.toString() ?? ''] = v;
              } catch (_) {
                // ignore keys that can't be stringified
              }
            });
            out.addAll(normalized);
          }
          _eventsController.add(out);
        } catch (e) {
          _log('forwardEvent failed for $evName: $e');
        }
      }

      for (final ev in ['message', 'thread_message', 'thread_created', 'chat_ready', 'booking_closed', 'chat_closed', 'typing', 'read']) {
        _socket!.on(ev, (data) => _forwardEvent(ev, data));
      }

      _socket!.onDisconnect((reason) async {
        try {
          final s = reason is String ? reason : jsonEncode(reason);
          _log('socket disconnected (full): $s');
        } catch (_) {
          _log('socket disconnected: $reason');
        }

        if (reason == 'io server disconnect') {
          _log('server requested disconnect; attempting refreshAuth');
          try {
            await AppStateNotifier.instance.refreshAuth();
          } catch (e) {
            _log('refreshAuth failed: $e');
          }

          Future.delayed(const Duration(seconds: 2), () async {
            final newToken = await TokenStorage.getToken();
            if (newToken != null && newToken.isNotEmpty) {
              try {
                _log('reconnecting with refreshed token');
                connect(newToken);
              } catch (e) {
                _log('reconnect after server disconnect failed: $e');
              }
            } else {
              _log('no token available after refresh; not reconnecting');
            }
          });
          return;
        }

        Future.delayed(const Duration(seconds: 5), () async {
          final tokenNow = await TokenStorage.getToken();
          if (tokenNow != null && tokenNow.isNotEmpty) {
            if (_socket == null || !_socket!.connected) {
              try {
                _log('reconnecting with token from storage');
                connect(tokenNow);
              } catch (e) {
                _log('reconnect attempt failed: $e');
              }
            }
          }
        });
      });

      // Register standard event handlers
      _socket?.on('connect', (_) {
        _log('RealtimeNotifications: connected');
        _eventsController.add({'event': 'connected'});
        // listen for typing and presence events from server
        try {
          _socket?.on('typing', (payload) {
            try {
              final p = (payload is Map) ? Map<String, dynamic>.from(payload) : (payload as dynamic);
              _log('RealtimeNotifications: received typing $p');
              _eventsController.add({'event': 'typing', 'payload': p});
            } catch (e) {}
          });
          _socket?.on('presence', (payload) {
            try {
              final p = (payload is Map) ? Map<String, dynamic>.from(payload) : (payload as dynamic);
              _log('RealtimeNotifications: received presence $p');
              _eventsController.add({'event': 'presence', 'payload': p});
            } catch (e) {}
          });
        } catch (_) {}
      });

      _socket!.connect();
    } catch (e) {
      _log('connect exception: $e');
      _connecting = false;
    }
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    try {
      _socket?.disconnect();
    } catch (_) {}
    _socket = null;
  }

  /// Show a local notification.
  // ignore: unused_element
  Future<void> _showLocalNotification(dynamic payload) async {
    if (!initialized) return;
    try {
      final title = payload['title']?.toString() ?? 'Notification';
      final body = payload['message']?.toString() ?? payload['text']?.toString() ?? '';
      final jsonPayload = jsonEncode(payload);

      const androidDetails = AndroidNotificationDetails(
        'rijhub_channel',
        'RijHub Notifications',
        channelDescription: 'Notifications from RijHub server',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      const iosDetails = DarwinNotificationDetails();
      const platform = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _local.show(0, title, body, platform, payload: jsonPayload);
    } catch (e) {
      _log('showLocalNotification error $e');
    }
  }

  /// Emit a notification payload to the server if socket is connected.
  /// This is a best-effort helper: it will silently fail if socket is not connected.
  Future<void> emitNotification(Map<String, dynamic> payload) async {
    try {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('notification', payload);
        _log('emitted notification payload');
      } else {
        _log('emitNotification: socket not connected');
      }
    } catch (e) {
      _log('emitNotification error: $e');
    }
  }

  /// Ask the server to join a thread room so this socket receives thread events.
  void joinThread(String threadId) {
    try {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('join', {'threadId': threadId});
       }
     } catch (e) {
       _log('joinThread error: $e');
     }
   }

   /// Ask the server to mark messages as read for a thread.
   void emitRead(String threadId, List<String> messageIds) {
     try {
       if (_socket != null && _socket!.connected) {
         final payload = {'threadId': threadId, 'messageIds': messageIds};
         _socket!.emit('read', payload);
       } else {
         _log('emitRead: socket not connected');
       }
     } catch (e) {
       _log('emitRead error: $e');
     }
   }

   /// Ask the server to leave a thread room. Some servers accept a 'leave'
   /// event which removes this socket from the thread room to avoid receiving
   /// further thread events. This is best-effort and will silently fail if the
   /// server doesn't support it.
   void leaveThread(String threadId) {
     try {
       if (threadId.isEmpty) return;
       if (_socket != null && _socket!.connected) {
         _socket!.emit('leave', {'threadId': threadId});
         _log('leaveThread emitted: $threadId');
       }
     } catch (e) {
       _log('leaveThread error: $e');
     }
   }

  /// Send a chat message via the socket (best-effort). Payload matches server expectations.
  void sendChatMessage(String threadId, String text) {
    try {
      if (_socket != null && _socket!.connected) {
        final payload = {'threadId': threadId, 'text': text};
        _socket!.emit('message', payload);
        _log('sendChatMessage emitted');
      } else {
        _log('sendChatMessage: socket not connected');
      }
    } catch (e) {
      _log('sendChatMessage error: $e');
    }
  }

  /// Emit typing state for a thread. typing=true indicates the user started typing.
  void emitTyping(String threadId, String userId, bool typing) {
    try {
      if (_socket != null && _socket!.connected) {
        final payload = {'threadId': threadId, 'userId': userId, 'typing': typing};
        _socket!.emit('typing', payload);
        _log('emitTyping: $payload');
      } else {
        _log('emitTyping: socket not connected');
      }
    } catch (e) {
      _log('emitTyping error: $e');
    }
  }

  /// Emit presence status for a user (online/offline/away)
  void emitPresence(String userId, String status) {
    try {
      if (_socket != null && _socket!.connected) {
        final payload = {'userId': userId, 'status': status};
        _socket!.emit('presence', payload);
        _log('emitPresence: $payload');
      } else {
        _log('emitPresence: socket not connected');
      }
    } catch (e) {
      _log('emitPresence error: $e');
    }
  }
}
