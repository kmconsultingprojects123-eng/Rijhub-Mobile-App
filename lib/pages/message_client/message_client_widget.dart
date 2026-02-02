import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/user_service.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/token_storage.dart';
import '../../api_config.dart';
import 'message_client_model.dart';
import '../../utils/app_notification.dart';
import '../../utils/realtime_notifications.dart';
export 'message_client_model.dart';

// Avoid importing package:flutter/foundation.dart because some analyzers
// in this workspace resolve package: URIs incorrectly; define a local
// const using the same semantics as kDebugMode instead.
const bool _kDebugMode = !const bool.fromEnvironment('dart.vm.product');

class MessageClientWidget extends StatefulWidget {
  final String? bookingId;
  final String? jobTitle;
  final String? bookingPrice;
  final String? bookingDateTime;
  final String? threadId;

  const MessageClientWidget({
    super.key,
    this.bookingId,
    this.jobTitle,
    this.bookingPrice,
    this.bookingDateTime,
    this.threadId,
  });

  static String routeName = 'messageClient';
  static String routePath = '/messageClient';

  @override
  State<MessageClientWidget> createState() => _MessageClientWidgetState();
}

class _MessageClientWidgetState extends State<MessageClientWidget> {
  late MessageClientModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Chat state
  List<Map<String, dynamic>> _messages = [];
  bool _loadingMessages = true;
  Timer? _pollTimer;
  String? _currentUserId;
  String? _currentUserRole;
  String? _threadId;
  String? _participantImageUrl;
  String? _participantName;
  String? _participantId;
  // whether the participant (artisan) is verified / KYCed
  bool _participantVerified = false;
  bool _waitingForThread = false;
  String? _bookingStatusFromThread;
  String? _bookingPriceFromThread;
  bool _sendingMessage = false;
  bool _bookingCompleted = false;
  bool _completing = false;
  bool _submittingReview = false;

  // Review conflict state: when server returns 409 (already reviewed)
  String? _reviewConflictMessage;
  bool _reviewAlreadySubmitted = false;

  // Diagnostic: last chat-related error/details to show to user for debugging
  String? _lastChatError;

  // Last known booking payment status observed while waiting for thread
  String? _lastBookingPaymentStatus;
  bool _didAttemptConfirmNudge = false; // avoid repeating backend nudge attempts
  // Realtime notifications handled by RealtimeNotifications (socket.io)
  int _reconnectAttempts = 0;
  bool _wsConnecting = false;
  // Background silent refresh timer (no UI loading indicators)
  Timer? _backgroundRefreshTimer;

    // Subscription for RealtimeNotifications events (socket.io)
    StreamSubscription<Map<String, dynamic>>? _rnSub;
    // Debug: last realtime event name and a small sub to update connection status for UI
    StreamSubscription<Map<String, dynamic>>? _rnDebugSub;
    String? _lastRealtimeEvent;
    bool _socketConnected = false;

  // Scroll controller
  final ScrollController _messagesScrollController = ScrollController();

  // Add a debouncer for send button to prevent multiple sends
  bool _sendButtonEnabled = true;
  Timer? _sendDebounceTimer;

  // --- Duplicate-send prevention ---
  // Remember the last text that was sent and when it was sent. This helps
  // suppress accidental duplicate taps or multiple event handlers firing
  // in quick succession (e.g. <2s).
  String? _lastSentText;
  DateTime? _lastSentAt;
  final Duration _duplicateSendWindow = const Duration(milliseconds: 500);

  // --- Typing & presence state ---
  bool _peerTyping = false; // whether the other participant is typing
  bool _peerOnline = false; // whether the other participant is online
  Timer? _typingStoppedTimer; // local timer to send typing:false after inactivity
  DateTime? _lastTypingSentAt; // throttle typing:true re-emits
  final Duration _typingStopWindow = const Duration(seconds: 2);
  final Duration _typingStartThrottle = const Duration(seconds: 5);
  StreamSubscription<Map<String, dynamic>>? _rnEventSub;

    @override
    void initState() {
    super.initState();
    _model = createModel(context, () => MessageClientModel());
    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();

    // Ensure realtime subsystem attempts to initialize early (best-effort)
    try {
      RealtimeNotifications.instance.init();
    } catch (_) {}

    // Debug subscription: keep UI updated with last event and connected state
    try {
      _rnDebugSub = RealtimeNotifications.instance.events.listen((ev) {
        try {
          final name = ev['event']?.toString() ?? ev.toString();
          _lastRealtimeEvent = name;
          _socketConnected = RealtimeNotifications.instance.connected;
          if (mounted) setState(() {});
        } catch (_) {}
      });
    } catch (_) {}

    // Watch text changes to emit typing events
    _model.textController?.addListener(_handleTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeInitChat());

    try {
      if (_kDebugMode) {
        debugPrint('MessageClient(init): widget.bookingId=${widget.bookingId ?? '<null>'} widget.threadId=${widget.threadId ?? '<null>'}');
      }
    } catch (_) {}

    _model.textFieldFocusNode?.addListener(_handleFocusChange);

    // Subscribe to socket.io event stream so we can handle realtime events consistently
    try {
      _rnSub = RealtimeNotifications.instance.events.listen((ev) {
        try {
          final eventName = ev['event']?.toString() ?? '';

          // Handle typing & presence events forwarded by RealtimeNotifications
          if (eventName == 'typing') {
            _handleTypingEvent(ev);
            return;
          }

          if (eventName == 'presence') {
            _handlePresenceEvent(ev);
            return;
          }

          if (eventName == 'thread_created' || eventName == 'chat_ready') {
            _handleThreadCreated(ev);
            return;
          }

          // Handle all message-related events in one place
          if (eventName == 'message' ||
              eventName == 'new_message' ||
              eventName == 'chat_message' ||
              eventName == 'thread_message') {
            _handleIncomingMessage(ev);
            return;
          }

          if (eventName == 'booking_closed' || eventName == 'chat_closed') {
            _handleBookingClosed();
            return;
          }
        } catch (e) {
          if (_kDebugMode) debugPrint('Error handling socket event: $e');
        }
      });
    } catch (e) {
      if (_kDebugMode) debugPrint('Error setting up socket listener: $e');
    }
    // Start a silent background refresh every 5s to keep messages updated
    // without showing loading indicators in the UI. If socket is connected
    // we'll skip polling because realtime events will arrive.
    try {
      _backgroundRefreshTimer?.cancel();
      _backgroundRefreshTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
        try {
          if (!mounted) return;
          if (_bookingCompleted) { _backgroundRefreshTimer?.cancel(); return; }
          // Prefer realtime socket; if connected, skip background polling
          if (RealtimeNotifications.instance.connected) return;
          // If there's an existing poll fallback timer active, skip to avoid duplicate requests
          if (_pollTimer != null && _pollTimer!.isActive) return;

          if (_threadId != null && _threadId!.isNotEmpty) {
            await _fetchChatByThreadIdInBackground();
          } else if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
            await _fetchChatInBackground();
          }
        } catch (e) {
          if (_kDebugMode) debugPrint('Background chat refresh error: $e');
        }
      });
    } catch (_) {}
    }

  void _handleTypingEvent(Map<String, dynamic> ev) {
    try {
      final payload = ev['payload'] ?? ev;
      final tid = payload is Map ? (payload['threadId']?.toString() ?? '') : '';
      final uid = payload is Map ? (payload['userId']?.toString() ?? '') : '';
      final typing = payload is Map ? (payload['typing'] == true) : false;

      // Only update UI if typing event relates to our thread and from other user
      if (tid == _threadId && uid != (_currentUserId ?? '')) {
        if (mounted) setState(() => _peerTyping = typing);
        if (typing) {
          // auto clear peer typing indicator after a short while in case server misses stop
          Timer(_typingStopWindow, () {
            if (mounted) setState(() => _peerTyping = false);
          });
        }
      }
    } catch (_) {}
  }

  void _handlePresenceEvent(Map<String, dynamic> ev) {
    try {
      final payload = ev['payload'] ?? ev;
      final uid = payload is Map ? (payload['userId']?.toString() ?? '') : '';
      final status = payload is Map ? (payload['status']?.toString() ?? '') : '';

      if (uid == _participantId) {
        if (mounted) setState(() => _peerOnline = status == 'online');
      }
    } catch (_) {}
  }

  void _handleThreadCreated(Map<String, dynamic> ev) {
    final tid = ev['threadId']?.toString();
    if (tid != null && tid.isNotEmpty) {
      _threadId = tid;
      try {
        if (_kDebugMode) debugPrint('RealtimeNotifications -> thread created. threadId=$_threadId');
      } catch (_) {}
      RealtimeNotifications.instance.joinThread(tid);
      if (mounted) setState(() {});
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> ev) {
    try {
      final rawMsg = ev['message'] ?? ev['payload'] ?? ev;
      final msg = (rawMsg is Map) ? Map<String, dynamic>.from(rawMsg) : null;

      if (msg != null) {
        // Check if this message belongs to our current thread
        final incomingTid = msg['threadId']?.toString() ?? msg['chatId']?.toString();
        if (incomingTid != null && incomingTid.isNotEmpty &&
            (_threadId == null || incomingTid != _threadId)) {
          if (_kDebugMode) debugPrint('Ignoring message for thread $incomingTid (current=$_threadId)');
          return;
        }

        // Check for duplicates
        if (_isDuplicateMessage(msg)) {
          if (_kDebugMode) debugPrint('Ignoring duplicate message: ${msg['_id']}');
          return;
        }

        if (mounted) {
          setState(() {
            _messages.add(msg);
            _loadingMessages = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error handling incoming message: $e');
    }
  }

  void _handleBookingClosed() {
    _bookingCompleted = true;
    try {
      RealtimeNotifications.instance.disconnect();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // announce offline presence
    try {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        RealtimeNotifications.instance.emitPresence(_currentUserId!, 'offline');
      }
    } catch (_) {}

    _pollTimer?.cancel();
    _backgroundRefreshTimer?.cancel();
    _sendDebounceTimer?.cancel();
    _typingStoppedTimer?.cancel();
    _model.textController?.removeListener(_handleTextChanged);

    try {
      RealtimeNotifications.instance.disconnect();
    } catch (_) {}

    _model.textFieldFocusNode?.removeListener(_handleFocusChange);
    _messagesScrollController.dispose();
    _model.dispose();
    _rnSub?.cancel();
    _rnSub = null;
    super.dispose();
  }

  void _handleFocusChange() {
    if (_model.textFieldFocusNode?.hasFocus ?? false) {
      // Consider user active while typing/has focus; emit online presence
      try {
        if (_currentUserId != null && _currentUserId!.isNotEmpty) {
          RealtimeNotifications.instance.emitPresence(_currentUserId!, 'online');
        }
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 200), () => _scrollToBottom());
    }
  }

  void _handleTextChanged() {
    try {
      final text = _model.textController?.text ?? '';
      final trimmed = text.trim();
      // If empty or booking completed, ensure typing false is emitted and timers cancelled
      if (trimmed.isEmpty || _bookingCompleted) {
        _cancelTypingTimersAndEmitFalse();
        return;
      }

      // Throttle typing:true re-emits to at most once per _typingStartThrottle
      final now = DateTime.now();
      if (_lastTypingSentAt == null ||
          now.difference(_lastTypingSentAt!) >= _typingStartThrottle) {
        // emit typing=true
        try {
          final uid = _currentUserId ?? '';
          if (_threadId != null && _threadId!.isNotEmpty && uid.isNotEmpty) {
            RealtimeNotifications.instance.emitTyping(_threadId!, uid, true);
            _lastTypingSentAt = now;
          }
        } catch (_) {}
      }

      // Reset stop timer: when it fires, we'll emit typing=false
      _typingStoppedTimer?.cancel();
      _typingStoppedTimer = Timer(_typingStopWindow, () {
        _cancelTypingTimersAndEmitFalse();
      });
    } catch (_) {}
  }

  void _cancelTypingTimersAndEmitFalse() {
    try {
      _typingStoppedTimer?.cancel();
      _typingStoppedTimer = null;
      final uid = _currentUserId ?? '';
      if (_threadId != null && _threadId!.isNotEmpty && uid.isNotEmpty) {
        RealtimeNotifications.instance.emitTyping(_threadId!, uid, false);
      }
    } catch (_) {}
  }

  Future<void> _maybeInitChat() async {
    try {
      final profile = await UserService.getProfile();
      _currentUserId = profile?['_id']?.toString() ?? profile?['id']?.toString();
      _currentUserRole = profile?['role']?.toString();
    } catch (_) {
      _currentUserId = null;
    }

    // Emit presence online when we know our user id and socket is ready
    try {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        // ensure RealtimeNotifications is initialized first
        try {
          await RealtimeNotifications.instance.init();
        } catch (_) {}

        try {
          RealtimeNotifications.instance.emitPresence(_currentUserId!, 'online');
        } catch (_) {}
      }
    } catch (_) {}

    if (widget.threadId != null && widget.threadId!.isNotEmpty) {
      _threadId = widget.threadId;
      try {
        if (_kDebugMode) debugPrint('MessageClient: using provided threadId=${_threadId}');
      } catch (_) {}
    }

    if (widget.bookingId != null && widget.bookingId!.isNotEmpty) {
      await _fetchChat();
      await _initWebSocketConnection();
    } else if (_threadId != null && _threadId!.isNotEmpty) {
      // If we only have a threadId (e.g., opened from notification), fetch by thread id
      await _fetchChatByThreadId();
      await _initWebSocketConnection();
    } else {
      setState(() {
        _loadingMessages = false;
        _messages = [];
      });
    }
  }

  Future<void> _initWebSocketConnection() async {
    // Use RealtimeNotifications (Socket.IO) helper. It handles auth in the
    // handshake and reconnection logic. We only need to ensure it's initialized
    // and that we join the thread room when we have a threadId.
    if (_wsConnecting) return;
    if (_threadId == null && (widget.bookingId == null || widget.bookingId!.isEmpty)) return;

    try {
      if (_kDebugMode) debugPrint('MessageClient: init websocket connection with threadId=${_threadId ?? '<null>'}');
    } catch (_) {}

    _wsConnecting = true;
    try {
      await RealtimeNotifications.instance.init();
      // If token and thread known, join thread so we receive realtime events
      if (_threadId != null && _threadId!.isNotEmpty) {
        RealtimeNotifications.instance.joinThread(_threadId!);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('MessageClient: realtime init failed -> $e; falling back to polling');
      _startPollingFallback();
    } finally {
      _wsConnecting = false;
    }
  }

  void _startPollingFallback() {
    try {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (mounted) await _fetchChat();
        if (_bookingCompleted) {
          _pollTimer?.cancel();
        }
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant MessageClientWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bookingChanged = (widget.bookingId ?? '') != (oldWidget.bookingId ?? '');
    final threadChanged = (widget.threadId ?? '') != (oldWidget.threadId ?? '');

    if (bookingChanged || threadChanged) {
      // Reset state
      _pollTimer?.cancel();
      _messages = [];
      _loadingMessages = true;
      _threadId = widget.threadId;

      // Leave old thread room
      if (oldWidget.threadId?.isNotEmpty == true) {
        RealtimeNotifications.instance.leaveThread(oldWidget.threadId!);
      }

      // Initialize chat
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeInitChat());
    } else {
      // If threadId was provided by parent after mount, ensure we join it.
      if (_threadId != null && _threadId!.isNotEmpty) {
        try {
          RealtimeNotifications.instance.joinThread(_threadId!);
        } catch (_) {}
      }
    }
  }

  Future<void> _fetchChat() async {
    if (widget.bookingId == null || widget.bookingId!.isEmpty) return;

    if (!_loadingMessages) {
      setState(() => _loadingMessages = true);
    }

    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        // No auth token available — this will make protected endpoints return 401.
        _lastChatError = 'Missing auth token. Please sign in.';
        if (_kDebugMode) debugPrint('MessageClient: getToken returned null — cannot fetch chat');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri = Uri.parse('$API_BASE_URL/api/chat/booking/${widget.bookingId}');
      if (_kDebugMode) debugPrint('MessageClient: GET $uri');

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // Surface HTTP-level diagnostics so _waitForThreadAvailable can show exact reason
        _lastChatError = 'Failed to fetch chat: HTTP ${resp.statusCode} ${resp.body}';
        if (_kDebugMode) debugPrint('MessageClient: _fetchChat non-2xx -> $_lastChatError');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      if (_kDebugMode) debugPrint('MessageClient: _fetchChat resp ${resp.statusCode}');

      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        final data = body is Map ? (body['data'] ?? body) : body;

        if (data is Map) {
          try {
            final isClosed = data['isClosed'];
            if (isClosed is bool && isClosed) {
              _bookingCompleted = true;
              try {
                RealtimeNotifications.instance.disconnect();
              } catch (_) {}
            }
          } catch (_) {}

          _threadId = data['threadId']?.toString() ?? data['_id']?.toString();
          if (_kDebugMode) debugPrint('MessageClient: _fetchChat set _threadId=$_threadId');

          // Extract participant info
          _extractParticipantInfo(Map<String, dynamic>.from(data));

          // Extract booking info
          _extractBookingInfo(Map<String, dynamic>.from(data));

          final msgs = <Map<String, dynamic>>[];
          final rawMsgs = (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) {
            if (m is Map) msgs.add(Map<String, dynamic>.from(m));
          }

          if (mounted) {
            setState(() {
              _messages = msgs;
              _loadingMessages = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
          return;
        }
      }

      setState(() {
        _messages = [];
        _loadingMessages = false;
      });
    } catch (e) {
      if (_kDebugMode) debugPrint('MessageClient: _fetchChat exception: $e');
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _extractParticipantInfo(Map<String, dynamic> data) {
    try {
      final parts = data['participants'];
      if (parts is List && parts.isNotEmpty) {
        String? otherName;
        String? otherImg;
        String? otherId;
        for (final p in parts) {
          if (p is Map) {
            final pid = p['_id']?.toString() ?? p['id']?.toString() ?? p['userId']?.toString();
            if (pid != null && pid.isNotEmpty && pid != (_currentUserId ?? '')) {
              otherName = p['name']?.toString() ?? p['fullName']?.toString() ?? otherName;
              otherImg = (p['profileImage'] is String)
                  ? p['profileImage']
                  : (p['profileImage'] is Map
                  ? (p['profileImage']['url'] ?? p['profileImage']['path'])
                  : null);
              otherId = pid;
              break;
            }
          }
        }
        _participantName = otherName ?? _participantName;
        _participantImageUrl = otherImg ?? _participantImageUrl;
        _participantId = otherId ?? _participantId;

        // Check and set participant verification status (artisan KYC)
        _participantVerified = data['verified'] == true;
      }
    } catch (_) {}
  }

  void _extractBookingInfo(Map<String, dynamic> data) {
    try {
      final bookingMeta = data['booking'] ?? data['bookingInfo'] ?? data['bookingMeta'];
      if (bookingMeta is Map) {
        _bookingStatusFromThread = bookingMeta['status']?.toString() ?? _bookingStatusFromThread;
        final priceVal = bookingMeta['price'] ?? bookingMeta['amount'] ?? bookingMeta['total'];
        if (priceVal != null) {
          if (priceVal is num) {
            _bookingPriceFromThread = '₦' + NumberFormat('#,##0', 'en_US').format(priceVal);
          } else {
            final s = priceVal.toString();
            final n = num.tryParse(s.replaceAll(RegExp(r'[^0-9.-]'), ''));
            if (n != null) {
              _bookingPriceFromThread = '₦' + NumberFormat('#,##0', 'en_US').format(n);
            } else {
              _bookingPriceFromThread = s;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchChatByThreadId() async {
    if (_threadId == null || _threadId!.isEmpty) return;

    if (!_loadingMessages) {
      setState(() => _loadingMessages = true);
    }

    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        _lastChatError = 'Missing auth token. Please sign in.';
        if (_kDebugMode) debugPrint('MessageClient: getToken returned null — cannot fetch chat by thread');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri = Uri.parse('$API_BASE_URL/api/chat/${_threadId}');
      if (_kDebugMode) debugPrint('MessageClient: GET thread $uri');

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _lastChatError = 'Failed to fetch chat by thread: HTTP ${resp.statusCode} ${resp.body}';
        if (_kDebugMode) debugPrint('MessageClient: _fetchChatByThreadId non-2xx -> $_lastChatError');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      final data = body is Map ? (body['data'] ?? body) : body;

      if (data is Map) {
        _threadId = data['_id']?.toString() ?? _threadId;
        _extractParticipantInfo(Map<String, dynamic>.from(data));

        final msgs = <Map<String, dynamic>>[];
        final rawMsgs = (data['messages'] is List) ? data['messages'] as List : [];
        for (final m in rawMsgs) {
          if (m is Map) msgs.add(Map<String, dynamic>.from(m));
        }

        if (mounted) {
          setState(() {
            _messages = msgs;
            _loadingMessages = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
        return;
      }

      setState(() {
        _messages = [];
        _loadingMessages = false;
      });
    } catch (e) {
      if (_kDebugMode) debugPrint('MessageClient: _fetchChatByThreadId exception: $e');
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  // Silent background fetch that updates messages without toggling loading UI
  Future<void> _fetchChatByThreadIdInBackground() async {
    try {
      if (_threadId == null || _threadId!.isEmpty) return;
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return;
      final headers = <String, String>{'Content-Type':'application/json','Authorization':'Bearer $token'};
      final uri = Uri.parse('$API_BASE_URL/api/chat/${_threadId}');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode >=200 && resp.statusCode <300 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        final data = body is Map ? (body['data'] ?? body) : body;
        if (data is Map) {
          final msgs = <Map<String,dynamic>>[];
          final rawMsgs = (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) if (m is Map) msgs.add(Map<String,dynamic>.from(m));
          if (!mounted) return;
          setState(() {
            _messages = msgs;
            // don't change _loadingMessages here so UI isn't affected
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Background _fetchChatByThreadId error: $e');
    }
  }

  // Silent background fetch for booking-based chat (when threadId not known)
  Future<void> _fetchChatInBackground() async {
    try {
      if (widget.bookingId == null || widget.bookingId!.isEmpty) return;
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return;
      final headers = <String, String>{'Content-Type':'application/json','Authorization':'Bearer $token'};
      final uri = Uri.parse('$API_BASE_URL/api/chat/booking/${widget.bookingId}');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode >=200 && resp.statusCode <300 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        final data = body is Map ? (body['data'] ?? body) : body;
        if (data is Map) {
          final msgs = <Map<String,dynamic>>[];
          final rawMsgs = (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) if (m is Map) msgs.add(Map<String,dynamic>.from(m));
          if (!mounted) return;
          // Update threadId/participant info silently as well
          try { _threadId = data['threadId']?.toString() ?? data['_id']?.toString() ?? _threadId; } catch (_) {}
          try { _extractParticipantInfo(Map<String,dynamic>.from(data)); } catch (_) {}
          try { _extractBookingInfo(Map<String,dynamic>.from(data)); } catch (_) {}
          setState(() { _messages = msgs; });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Background _fetchChat error: $e');
    }
  }

  Future<void> _notifyMessageSent(String text) async {
    try {
      // Prefer to send chat messages over the socket if connected and threadId is known.
      if (RealtimeNotifications.instance.connected && _threadId != null && _threadId!.isNotEmpty) {
        try {
          // Ensure socket is ready
          if (!RealtimeNotifications.instance.connected) {
            await RealtimeNotifications.instance.init();
          }

          // Use the sendChatMessage method (fire-and-forget: method is void)
          RealtimeNotifications.instance.sendChatMessage(_threadId!, text);
          if (_kDebugMode) debugPrint('notifyMessageSent: sent via socket for thread=$_threadId');
          return;
        } catch (e) {
          if (_kDebugMode) debugPrint('notifyMessageSent socket send error: $e');
        }
      }

      // Fallback: emit a notification event (server may handle this) so the other
      // participant gets notified even if socket message failed.
      final payload = <String, dynamic>{
        'type': 'chat_message',
        'threadId': _threadId,
        'bookingId': widget.bookingId,
        'from': _currentUserId,
        'to': _participantId,
        'message': text,
        'title': widget.jobTitle ?? 'New message',
      };
      await RealtimeNotifications.instance.emitNotification(payload);
      if (_kDebugMode) debugPrint('notifyMessageSent: emitted notification fallback');
    } catch (e) {
      if (_kDebugMode) debugPrint('notifyMessageSent error: $e');
    }
  }

  Future<bool> _waitForThreadAvailable({
    int attempts = 3,
    Duration delay = const Duration(seconds: 1)
  }) async {
    if (widget.bookingId == null || widget.bookingId!.isEmpty) return false;

    try {
      for (int i = 0; i < attempts; i++) {
        if (_kDebugMode) debugPrint('MessageClient: waitForThreadAvailable attempt ${i + 1}/${attempts} currentThreadId=${_threadId}');

        // If we already have a thread, we're done
        if (_threadId != null && _threadId!.isNotEmpty) return true;

        // Fetch latest chat info which will set _threadId if created
        await _fetchChat();
        if (_kDebugMode) debugPrint('MessageClient: after _fetchChat threadId=${_threadId} lastChatError=${_lastChatError}');

        if (_threadId != null && _threadId!.isNotEmpty) return true;

        // If we got a 404 "Thread not found" but booking is paid, try nudging the backend once
        if (!_didAttemptConfirmNudge && _lastChatError != null &&
            (_lastChatError!.toLowerCase().contains('404') ||
                _lastChatError!.toLowerCase().contains('thread not found'))) {
          await _attemptConfirmNudge();
        }

        // wait before next attempt
        await Future.delayed(delay);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('waitForThreadAvailable error: $e');
    }

    return _threadId != null && _threadId!.isNotEmpty;
  }

  Future<void> _attemptConfirmNudge() async {
    try {
      // Check booking payment status first
      final token = await TokenStorage.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final parsed = jsonDecode(resp.body);
        final booking = parsed is Map ? (parsed['data'] ?? parsed) : parsed;

        if (booking is Map) {
          final payStatus = (booking['paymentStatus'] ?? booking['payment'] ?? '').toString().toLowerCase();
          _lastBookingPaymentStatus = payStatus;

          if (payStatus == 'paid') {
            // Attempt to nudge backend to create/confirm booking resources (idempotent)
            try {
              final confirmUri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}/confirm-payment');
              if (_kDebugMode) debugPrint('MessageClient: nudging backend confirm-payment $confirmUri');

              final nresp = await http.post(confirmUri, headers: headers).timeout(const Duration(seconds: 8));
              if (_kDebugMode) debugPrint('MessageClient: confirm nudge resp ${nresp.statusCode} ${nresp.body}');
            } catch (e) {
              if (_kDebugMode) debugPrint('MessageClient: confirm nudge failed: $e');
            }
            _didAttemptConfirmNudge = true;
          } else {
            // booking not paid yet — chat won't exist until webhook runs
            if (_kDebugMode) debugPrint('Chat not ready: booking paymentStatus=$payStatus');
            _lastChatError = 'Chat not ready: booking paymentStatus=$payStatus';
          }
        }
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Booking status check / nudge error: $e');
    }
  }

  Future<void> _sendMessage() async {
    // Prevent multiple simultaneous sends
    if (!_sendButtonEnabled || _sendingMessage || _waitingForThread) {
      return;
    }

    final text = _model.textController?.text ?? '';
    if (text.trim().isEmpty) return;

    // Suppress duplicates
    try {
      final ttrim = text.trim();
      if (_lastSentText != null && _lastSentAt != null) {
        if (_lastSentText!.trim() == ttrim &&
            DateTime.now().difference(_lastSentAt!) <= _duplicateSendWindow) {
          // ignore duplicate
          if (_kDebugMode) debugPrint('Ignoring duplicate send for "$ttrim"');
          return;
        }
      }
    } catch (_) {}

    // Disable send button temporarily to prevent multiple clicks
    setState(() {
      _sendButtonEnabled = false;
      _sendingMessage = true;
    });

    // Mark this text as "just sent" so any near-simultaneous attempts are ignored
    try {
      _lastSentText = text;
      _lastSentAt = DateTime.now();
    } catch (_) {}

    // Cancel any existing debounce timer
    _sendDebounceTimer?.cancel();

    // Set a debounce timer to re-enable the button after 2 seconds
    _sendDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _sendButtonEnabled = true;
        });
      }
    });

    // Add temporary message for immediate feedback
    final tempMessage = {
      '_id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'text': text.trim(),
      'senderId': _currentUserId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'isLocal': true,
    };

    setState(() {
      _messages.add(tempMessage);
    });
    _scrollToBottom();
    _model.textController?.clear();

    try {
      // If we don't yet have a thread id, try fetching the chat for this booking
      if (_threadId == null || _threadId!.isEmpty) {
        final scaffold = ScaffoldMessenger.of(context);
        // show preparing snackbar and spinner
        setState(() => _waitingForThread = true);
        scaffold.showSnackBar(const SnackBar(
          content: Text('Preparing chat...'),
          duration: Duration(hours: 1),
        ));

        final got = await _waitForThreadAvailable(attempts: 4, delay: const Duration(seconds: 1));

        // hide preparing snackbar
        scaffold.hideCurrentSnackBar();
        setState(() => _waitingForThread = false);

        if (!got) {
          final err = _lastChatError ?? 'Unable to send message — chat not ready.';
          final composed = '$err\n\nContext: bookingId=${widget.bookingId ?? 'null'} threadId=${_threadId ?? 'null'} lastBookingPaymentStatus=${_lastBookingPaymentStatus ?? 'unknown'}';
          _lastChatError = composed;
          await _showChatErrorDialog(composed);

          // Remove temp message
          setState(() {
            _messages.removeWhere((m) => m['_id'] == tempMessage['_id']);
          });
          return;
        }
      }

      // Use HTTP POST as the primary reliable send mechanism.
      await _sendMessageHttp(text);
    } catch (e) {
      // Remove temp message on error
      setState(() {
        _messages.removeWhere((m) => m['_id'] == tempMessage['_id']);
      });
      AppNotification.showError(context, 'Error sending message');
    } finally {
      if (mounted) {
        setState(() {
          _sendingMessage = false;
          // Button will be re-enabled by the debounce timer
        });
      }
    }
  }

  Future<void> _sendMessageHttp(String text) async {
    final token = await TokenStorage.getToken();
    if (token == null || token.isEmpty) {
      final composed = 'Cannot send message: missing auth token. Please login.';
      _lastChatError = composed;
      await _showChatErrorDialog(composed);
      return;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };

    // Ensure we have a threadId to post to
    if (_threadId == null || _threadId!.isEmpty) {
      final scaffold = ScaffoldMessenger.of(context);
      setState(() => _waitingForThread = true);
      scaffold.showSnackBar(const SnackBar(
        content: Text('Preparing chat...'),
        duration: Duration(hours: 1),
      ));

      final got = await _waitForThreadAvailable(attempts: 4, delay: const Duration(seconds: 1));
      scaffold.hideCurrentSnackBar();
      setState(() => _waitingForThread = false);

      if (!got) {
        final err = _lastChatError ?? 'Unable to send message — chat not ready.';
        final composed = '$err\n\nContext: bookingId=${widget.bookingId ?? 'null'} threadId=${_threadId ?? 'null'} lastBookingPaymentStatus=${_lastBookingPaymentStatus ?? 'unknown'}';
        _lastChatError = composed;
        await _showChatErrorDialog(composed);
        return;
      }
    }

    // Ensure socket is connected for realtime notifications
    try {
      if (!RealtimeNotifications.instance.connected) {
        await RealtimeNotifications.instance.init();
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Failed to init socket: $e');
    }

    final uri = Uri.parse('$API_BASE_URL/api/chat/${_threadId!}');
    final body = jsonEncode({'text': text.trim()});

    if (_kDebugMode) {
      debugPrint('MessageClient: POST $uri body=$body');
      debugPrint('Sending message - Thread ID: $_threadId');
      debugPrint('Socket connected: ${RealtimeNotifications.instance.connected}');
    }

    try {
      final resp = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));

      if (_kDebugMode) debugPrint('MessageClient: send resp ${resp.statusCode} ${resp.body}');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Try to extract the saved message from response to append locally.
        try {
          final parsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
          dynamic saved;

          if (parsed is Map) {
            // Common shapes: { data: <message> } or { success: true, data: { message: ... } }
            if (parsed['data'] != null) {
              saved = parsed['data'];
              // Some APIs return data: { message: <msg> }
              if (saved is Map && saved['message'] != null &&
                  (saved['message'] is Map || saved['message'] is String)) {
                saved = saved['message'];
              }
            } else if (parsed['message'] != null) {
              saved = parsed['message'];
            } else {
              saved = parsed;
            }
          } else {
            saved = parsed;
          }

          Map<String, dynamic>? msgObj;
          if (saved is Map) {
            msgObj = Map<String, dynamic>.from(saved);
          } else if (saved is String) {
            msgObj = {
              'text': saved,
              'message': saved,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'senderId': _currentUserId
            };
          }

          // Remove temp message
          setState(() {
            _messages.removeWhere((m) => m['isLocal'] == true);

            if (msgObj != null) {
              _messages.add(msgObj!);
            }
            _loadingMessages = false;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

          // Best-effort notify via socket
          _notifyMessageSent(text.trim());

          // Join thread if not already joined
          try {
            if (_threadId != null && _threadId!.isNotEmpty) {
              RealtimeNotifications.instance.joinThread(_threadId!);
            }
          } catch (_) {}
        } catch (e) {
          // If parsing fails, refresh thread as fallback
          try {
            await _fetchChat();
            _scrollToBottom();
            _notifyMessageSent(text.trim());
            if (_threadId != null && _threadId!.isNotEmpty) {
              RealtimeNotifications.instance.joinThread(_threadId!);
            }
          } catch (_) {}
        }
      } else {
        String msg = 'Failed to send message';
        try {
          final parsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) {
            msg = (parsed['message'] ?? parsed['error']).toString();
          } else if (resp.body.isNotEmpty) {
            msg = resp.body;
          }
        } catch (_) {}

        final detailed = 'POST $uri -> ${resp.statusCode} ${resp.body}';
        _lastChatError = detailed;

        if (_kDebugMode) debugPrint('sendMessageHttp failed: $detailed');

        // Show appropriate error message
        if (resp.statusCode == 401) {
          msg = 'Session expired. Please login again';
        } else if (resp.statusCode == 404) {
          msg = 'Chat not found. Please refresh.';
        }

        await _showChatErrorDialog('$msg\n\nFull response:\n$detailed');
      }
    } catch (e) {
      final detailed = 'sendMessageHttp exception: $e';
      _lastChatError = detailed;
      if (_kDebugMode) debugPrint(detailed);
      await _showChatErrorDialog(
          'Network error — please check your connection\n\nException:\n$detailed');
    }
  }

  bool _isDuplicateMessage(Map<String, dynamic> msg) {
    try {
      final incomingId = msg['_id']?.toString();
      final incomingText = msg['text']?.toString() ?? msg['message']?.toString();
      final incomingTime = msg['createdAt']?.toString() ?? msg['timestamp']?.toString();

      // Check if we already have this message
      for (final existing in _messages) {
        if (existing['_id']?.toString() == incomingId) return true;
        if (existing['text']?.toString() == incomingText &&
            existing['createdAt']?.toString() == incomingTime) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _scrollToBottom({Duration delay = const Duration(milliseconds: 100)}) {
    try {
      Future.delayed(delay, () {
        if (!_messagesScrollController.hasClients) return;
        _messagesScrollController.animateTo(
          _messagesScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    } catch (_) {}
  }

  Widget _buildMessagesWidget() {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Responsive message width
    final screenWidth = MediaQuery.of(context).size.width;
    final messageMaxWidth = screenWidth < 400
        ? screenWidth * 0.75
        : screenWidth * 0.7;

    if (_loadingMessages) {
      return ListView.separated(
        controller: _messagesScrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(
            horizontal: screenWidth < 360 ? 8 : 0,
          ),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Padding(
            padding: EdgeInsets.all(screenWidth < 360 ? 10 : 12.0),
            child: Row(children: [
              Container(
                width: screenWidth < 360 ? 32 : 40,
                height: screenWidth < 360 ? 32 : 40,
                decoration: BoxDecoration(
                  color: theme.alternate.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: screenWidth < 360 ? 8 : 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: screenWidth < 360 ? 10 : 12,
                        width: screenWidth * 0.3,
                        decoration: BoxDecoration(
                          color: theme.alternate.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(height: screenWidth < 360 ? 6 : 8),
                      Container(
                        height: screenWidth < 360 ? 8 : 10,
                        width: screenWidth * 0.4,
                        decoration: BoxDecoration(
                          color: theme.alternate.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    ]),
              ),
            ]),
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(screenWidth < 360 ? 16 : 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: screenWidth < 360 ? 48 : 56,
                color: theme.secondaryText,
              ),
              SizedBox(height: screenWidth < 360 ? 8 : 12),
              Text(
                'No messages yet',
                style: theme.titleLarge.copyWith(
                  fontSize: screenWidth < 360 ? 18 : 20,
                ),
              ),
              SizedBox(height: screenWidth < 360 ? 6 : 8),
              Text(
                'Start the conversation by sending a message',
                textAlign: TextAlign.center,
                style: theme.bodyMedium.copyWith(
                  color: theme.secondaryText.withOpacity(0.7),
                  fontSize: screenWidth < 360 ? 13 : 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _messagesScrollController,
      padding: const EdgeInsets.only(bottom: 8.0),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final m = _messages[i];
        // Skip temporary messages that are being sent
        if (m['isLocal'] == true) {
          return _buildSendingMessage(m, theme, screenWidth);
        }

        final senderId = m['senderId']?.toString();
        final senderName = (m['senderName'] ?? m['sender'])?.toString() ?? '';
        final messageText = (m['message'] ?? m['text'] ?? '').toString();
        final timestamp = m['timestamp']?.toString();
        final isMe = (_currentUserId != null && senderId == _currentUserId);
        final timeStr = () {
          try {
            final dt = DateTime.tryParse(timestamp ?? '');
            if (dt != null) return DateFormat('h:mm a').format(dt);
          } catch (_) {}
          return '';
        }();

        final messageDate = () {
          try {
            final dt = DateTime.tryParse(timestamp ?? '');
            if (dt != null) return DateFormat('MMM d').format(dt);
          } catch (_) {}
          return '';
        }();

        // Show date header if this is first message or date changed
        final showDateHeader = i == 0 ||
            (DateTime.tryParse(_messages[i - 1]['timestamp'] ?? '')?.day !=
                DateTime.tryParse(timestamp ?? '')?.day);

        return Column(
          children: [
            if (showDateHeader)
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: screenWidth < 360 ? 8.0 : 12.0,
                  horizontal: screenWidth < 360 ? 8 : 0,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth < 360 ? 10.0 : 12.0,
                    vertical: screenWidth < 360 ? 4.0 : 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: Text(
                    messageDate,
                    style: theme.bodySmall.copyWith(
                      color: theme.secondaryText,
                      fontSize: screenWidth < 360 ? 10.0 : 12.0,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: 4.0,
                horizontal: screenWidth < 360 ? 8 : 0,
              ),
              child: Row(
                mainAxisAlignment: isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: CircleAvatar(
                        radius: screenWidth < 360 ? 14 : 18,
                        backgroundImage: m['senderImageUrl'] != null
                            ? NetworkImage(m['senderImageUrl'].toString())
                            : null,
                        backgroundColor: theme.alternate,
                        child: m['senderImageUrl'] == null
                            ? Icon(
                          Icons.person,
                          size: screenWidth < 360 ? 14 : 18,
                          color: theme.secondaryText,
                        )
                            : null,
                      ),
                    ),
                  ],
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: messageMaxWidth,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? theme.primary
                            : (isDark
                            ? const Color(0xFF374151)
                            : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(18.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(screenWidth < 360 ? 10 : 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe && senderName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Text(
                                senderName,
                                style: theme.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isMe
                                      ? Colors.white.withOpacity(0.9)
                                      : theme.secondaryText,
                                  fontSize: screenWidth < 360 ? 11 : 12,
                                ),
                              ),
                            ),
                          Text(
                            messageText,
                            style: theme.bodyMedium.copyWith(
                              color: isMe
                                  ? Colors.white
                                  : theme.primaryText,
                              height: 1.4,
                              fontSize: screenWidth < 360 ? 14 : 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              timeStr,
                              style: theme.bodySmall.copyWith(
                                color: isMe
                                    ? Colors.white.withOpacity(0.8)
                                    : theme.secondaryText,
                                fontSize: screenWidth < 360 ? 9.0 : 10.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: CircleAvatar(
                        radius: screenWidth < 360 ? 14 : 18,
                        backgroundColor: theme.primary.withOpacity(0.1),
                        child: Icon(
                          Icons.person,
                          size: screenWidth < 360 ? 14 : 18,
                          color: theme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSendingMessage(Map<String, dynamic> m, FlutterFlowTheme theme, double screenWidth) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 4.0,
        horizontal: screenWidth < 360 ? 8 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth < 400 ? screenWidth * 0.75 : screenWidth * 0.7,
              ),
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.7),
                borderRadius: BorderRadius.circular(18.0),
              ),
              padding: EdgeInsets.all(screenWidth < 360 ? 10 : 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m['text']?.toString() ?? '',
                    style: theme.bodyMedium.copyWith(
                      color: Colors.white,
                      fontSize: screenWidth < 360 ? 14 : 15,
                    ),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final theme = FlutterFlowTheme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    if (!_peerTyping) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 6 : 8),
      child: Row(
        children: [
          SizedBox(width: isSmallScreen ? 8 : 12),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Text(
            '${_participantName ?? 'Participant'} is typing...',
            style: theme.bodySmall.copyWith(color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    // If neither booking nor thread id provided, show friendly message
    final hasBooking = widget.bookingId != null && widget.bookingId!.isNotEmpty;
    final hasThread = widget.threadId != null && widget.threadId!.isNotEmpty;

    if (!hasBooking && !hasThread) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: theme.secondaryBackground,
          leading: FlutterFlowIconButton(
            borderColor: Colors.transparent,
            borderRadius: 20.0,
            borderWidth: 1.0,
            buttonSize: 40.0,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: theme.primaryText,
              size: 24.0,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Chat', style: theme.titleMedium),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: isSmallScreen ? 48 : 64,
                  color: theme.secondaryText,
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                Text(
                  'No chat context',
                  style: theme.titleLarge.copyWith(
                    fontSize: isSmallScreen ? 18 : 20,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text(
                  'This chat was opened without a booking or thread id. Open chat from the booking details or notification to start messaging.',
                  textAlign: TextAlign.center,
                  style: theme.bodyMedium.copyWith(
                    fontSize: isSmallScreen ? 13 : 14,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Go back',
                    style: TextStyle(fontSize: isSmallScreen ? 14 : 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.secondaryBackground,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderColor: Colors.transparent,
            borderRadius: 20.0,
            borderWidth: 1.0,
            buttonSize: isSmallScreen ? 36 : 40.0,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: theme.primaryText,
              size: isSmallScreen ? 20 : 24.0,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              CircleAvatar(
                radius: isSmallScreen ? 16 : 20,
                backgroundImage: _participantImageUrl != null &&
                    _participantImageUrl!.isNotEmpty
                    ? NetworkImage(_participantImageUrl!) as ImageProvider
                    : null,
                backgroundColor: theme.alternate,
                child: Stack(
                  children: [
                    if (_participantImageUrl == null ||
                        _participantImageUrl!.isEmpty)
                      Icon(
                        Icons.person,
                        color: theme.secondaryText,
                        size: isSmallScreen ? 16 : 20,
                      ),
                    // presence indicator (small dot)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _peerOnline ? theme.success : theme.alternate,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.primaryBackground, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isSmallScreen ? 8 : 12.0),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _participantName ?? widget.jobTitle ?? 'Chat',
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium.override(
                        fontFamily: 'Inter',
                        fontSize: isSmallScreen ? 14.0 : 16.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (((_bookingPriceFromThread ?? widget.bookingPrice) != null) ||
                        widget.bookingDateTime != null ||
                        _bookingStatusFromThread != null)
                      Text(
                        [
                          _bookingPriceFromThread ?? widget.bookingPrice,
                          widget.bookingDateTime,
                          _bookingStatusFromThread,
                        ].where((e) => e != null && e.toString().isNotEmpty).join(' • '),
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall.override(
                          fontFamily: 'Inter',
                          color: theme.secondaryText,
                          fontSize: isSmallScreen ? 10.0 : 12.0,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Connection status button (shows connected state and allows manual reconnect)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 8, 0),
              child: IconButton(
                tooltip: _lastRealtimeEvent != null ? 'Last event: $_lastRealtimeEvent' : 'Realtime status',
                icon: Icon(
                  RealtimeNotifications.instance.connected || _socketConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: RealtimeNotifications.instance.connected || _socketConnected ? theme.success : theme.secondaryText,
                  size: isSmallScreen ? 16 : 20,
                ),
                onPressed: () async {
                  // Try to init/connect and join current thread if available
                  try {
                    await RealtimeNotifications.instance.init();
                    if (_threadId != null && _threadId!.isNotEmpty) {
                      RealtimeNotifications.instance.joinThread(_threadId!);
                    }
                    setState(() {
                      _socketConnected = RealtimeNotifications.instance.connected;
                    });
                    final snack = ScaffoldMessenger.of(context);
                    snack.showSnackBar(SnackBar(content: Text('Realtime: ${RealtimeNotifications.instance.connected ? 'connected' : 'disconnected'}')));
                  } catch (e) {
                    if (_kDebugMode) debugPrint('Manual reconnect failed: $e');
                    final snack = ScaffoldMessenger.of(context);
                    snack.showSnackBar(SnackBar(content: Text('Realtime reconnect failed: $e')));
                  }
                },
              ),
            ),
          ],
          centerTitle: false,
          elevation: 0.5,
          shadowColor: Colors.black.withOpacity(0.1),
        ),
        body: SafeArea(
          top: true,
          child: Column(
            children: [
              // Booking status bar
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12.0 : 16.0,
                  vertical: isSmallScreen ? 8.0 : 12.0,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _bookingCompleted
                        ? [
                      theme.alternate.withOpacity(0.1),
                      theme.alternate.withOpacity(0.05)
                    ]
                        : [
                      theme.success.withOpacity(0.1),
                      theme.success.withOpacity(0.05)
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(color: theme.alternate.withOpacity(0.1)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _bookingCompleted ? Icons.check_circle_outline : Icons.check_circle,
                      color: _bookingCompleted ? theme.secondaryText : theme.success,
                      size: isSmallScreen ? 16 : 20.0,
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        _bookingCompleted
                            ? 'Booking completed - Chat is now read-only'
                            : 'Booking active - You can chat now',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: theme.bodySmall.override(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          color: _bookingCompleted ? theme.secondaryText : theme.success,
                          fontSize: isSmallScreen ? 12.0 : 13.0,
                        ),
                      ),
                    ),
                    if ((_currentUserRole ?? '').toLowerCase() == 'customer' ||
                        (_currentUserRole ?? '').toLowerCase() == 'client')
                      SizedBox(
                        height: isSmallScreen ? 32 : 36,
                        child: ElevatedButton(
                          onPressed: (_bookingCompleted || _completing)
                              ? null
                              : () async {
                            if (!mounted) return;
                            setState(() => _completing = true);
                            await _markJobComplete();
                            if (mounted) setState(() => _completing = false);
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _bookingCompleted
                                ? theme.alternate.withOpacity(0.3)
                                : theme.primary,
                            foregroundColor:
                            _bookingCompleted ? theme.secondaryText : Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 12 : 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
                            ),
                          ),
                          child: _buildMarkCompleteChild(),
                        ),
                      ),
                  ],
                ),
              ),

              // Messages list
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    isSmallScreen ? 8.0 : 16.0,
                    isSmallScreen ? 12.0 : 16.0,
                    isSmallScreen ? 8.0 : 16.0,
                    0.0,
                  ),
                  child: Column(
                    children: [
                      Expanded(child: _buildMessagesWidget()),
                      _buildTypingIndicator(),
                    ],
                  ),
                ),
              ),

              // Input area
              SafeArea(
                top: false,
                bottom: true,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    border: Border(
                      top: BorderSide(
                        color: theme.alternate.withOpacity(0.1),
                        width: 1.0,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.1 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.primaryBackground,
                              borderRadius: BorderRadius.circular(isSmallScreen ? 20 : 24.0),
                              border: Border.all(color: theme.alternate.withOpacity(0.2)),
                            ),
                            child: TextFormField(
                              controller: _model.textController,
                              focusNode: _model.textFieldFocusNode,
                              autofocus: false,
                              obscureText: false,
                              enabled: !_bookingCompleted,
                              readOnly: _bookingCompleted,
                              decoration: InputDecoration(
                                hintText: _bookingCompleted
                                    ? 'Chat closed - booking completed'
                                    : 'Type your message...',
                                hintStyle: theme.bodyMedium.override(
                                  fontFamily: 'Inter',
                                  color: _bookingCompleted ? theme.error : theme.secondaryText,
                                  fontSize: isSmallScreen ? 13 : 14.0,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsetsDirectional.fromSTEB(
                                  isSmallScreen ? 12.0 : 16.0,
                                  isSmallScreen ? 12.0 : 14.0,
                                  isSmallScreen ? 12.0 : 16.0,
                                  isSmallScreen ? 12.0 : 14.0,
                                ),
                              ),
                              style: theme.bodyMedium.override(
                                fontFamily: 'Inter',
                                fontSize: isSmallScreen ? 13 : 14.0,
                              ),
                              maxLines: 4,
                              minLines: 1,
                              validator: _model.textControllerValidator.asValidator(context),
                              onFieldSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        SizedBox(width: isSmallScreen ? 8 : 12),
                        Container(
                          width: isSmallScreen ? 42 : 48,
                          height: isSmallScreen ? 42 : 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (!_sendButtonEnabled ||
                                _sendingMessage ||
                                _waitingForThread ||
                                (_model.textController?.text.trim().isEmpty ?? true) ||
                                _bookingCompleted)
                                ? theme.alternate.withOpacity(0.3)
                                : theme.primary,
                          ),
                          child: IconButton(
                            icon: (_sendingMessage || _waitingForThread)
                                ? SizedBox(
                              width: isSmallScreen ? 16 : 20,
                              height: isSmallScreen ? 16 : 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : Icon(
                              Icons.send_rounded,
                              color: (!_sendButtonEnabled ||
                                  _sendingMessage ||
                                  _waitingForThread ||
                                  (_model.textController?.text.trim().isEmpty ?? true) ||
                                  _bookingCompleted)
                                  ? theme.secondaryText
                                  : Colors.white,
                              size: isSmallScreen ? 18 : 20.0,
                            ),
                            onPressed: (!_sendButtonEnabled ||
                                _sendingMessage ||
                                _waitingForThread ||
                                (_model.textController?.text.trim().isEmpty ?? true) ||
                                _bookingCompleted)
                                ? null
                                : () async => await _sendMessage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper UI & actions ---
  Future<void> _showChatErrorDialog(String error) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chat Error'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text(error),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    scaffold.showSnackBar(const SnackBar(content: Text('Error details copied to clipboard.')));
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Copy to clipboard'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            )
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _markJobComplete() async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        AppNotification.showError(context, 'Please login to mark job complete');
        return;
      }

      if (widget.bookingId == null || widget.bookingId!.isEmpty) {
        AppNotification.showError(context, 'No booking selected');
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}/complete');
      final payload = jsonEncode({ 'sendEmail': true });
      final response = await http.post(uri, headers: headers, body: payload).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppNotification.showSuccess(context, 'Booking marked as completed');
        if (mounted) {
          setState(() {
            _bookingCompleted = true;
          });
        }

        // After marking complete, prompt the customer to rate/review the artisan
        try {
          // small delay to allow UI update before showing bottom sheet
          if (mounted) await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) await _showRatingBottomSheet();
        } catch (_) {}
      } else {
        // Try to extract error message from response
        String serverMsg = 'Failed to mark booking as complete';
        try {
          final parsed = response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          } else if (response.body.isNotEmpty) {
            serverMsg = response.body;
          }
        } catch (_) {}
        AppNotification.showError(context, serverMsg);
      }
    } catch (e) {
      print(e);
      AppNotification.showError(context, 'Error: $e');
    }
  }

  // Show a bottom sheet allowing the user to rate (1-5) and leave a comment for the artisan.
  Future<void> _showRatingBottomSheet() async {
    if (_participantId == null || _participantId!.isEmpty) {
      AppNotification.showError(context, 'No artisan found to review');
      return;
    }

    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 360;
    final isLargeScreen = screenWidth > 600;

    final displayName = _participantName ?? 'Artisan';
    final displayJob = widget.jobTitle ?? '';
    final avatarUrl = _participantImageUrl;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (sheetContext) {
        int selectedRating = 5;
        final TextEditingController _reviewCtrl = TextEditingController();
        bool submitting = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F2937)
                    : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + (isSmallScreen ? 16 : 20),
                  left: isSmallScreen ? 16 : 24,
                  right: isSmallScreen ? 16 : 24,
                  top: 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: isSmallScreen ? 36 : 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF4B5563)
                                : const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Header with avatar and info
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar with better styling
                          Container(
                            width: isSmallScreen ? 56 : 64,
                            height: isSmallScreen ? 56 : 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.primary.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: isSmallScreen ? 26 : 30,
                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? NetworkImage(avatarUrl) as ImageProvider
                                  : null,
                              backgroundColor: isDark
                                  ? const Color(0xFF374151)
                                  : const Color(0xFFF3F4F6),
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Icon(
                                Icons.person,
                                size: isSmallScreen ? 28 : 32,
                                color: isDark
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF6B7280),
                              )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Name with verified badge if applicable
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        style: isSmallScreen
                                            ? theme.titleMedium.override(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF111827),
                                        )
                                            : theme.titleLarge.override(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF111827),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_participantVerified) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.verified,
                                        size: isSmallScreen ? 14 : 16,
                                        color: Colors.green,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (displayJob.isNotEmpty)
                                  Text(
                                    displayJob,
                                    style: theme.bodySmall.override(
                                      color: isDark
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFF6B7280),
                                      fontSize: isSmallScreen ? 12 : 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                if (_bookingPriceFromThread != null)
                                  Text(
                                    _bookingPriceFromThread!,
                                    style: theme.bodySmall.override(
                                      color: theme.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: isSmallScreen ? 12 : 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Close button
                          IconButton(
                            onPressed: () {
                              if (Navigator.of(sheetContext).canPop()) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              size: isSmallScreen ? 20 : 22,
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF6B7280),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Title and instructions
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Rate the service',
                            style: theme.titleLarge.override(
                              fontSize: isSmallScreen ? 18 : 20,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'How was your experience?',
                            style: theme.bodyMedium.override(
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF6B7280),
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap to select a rating',
                            style: theme.bodySmall.override(
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF6B7280),
                              fontSize: isSmallScreen ? 11 : 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Star selector with better styling
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF111827)
                                : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF374151)
                                  : const Color(0xFFE5E7EB),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Column(
                            children: [
                              // Rating number display
                              Text(
                                selectedRating.toString(),
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 32 : 40,
                                  fontWeight: FontWeight.w700,
                                  color: selectedRating >= 4
                                      ? const Color(0xFF10B981) // Green for good ratings
                                      : selectedRating >= 3
                                      ? const Color(0xFFF59E0B) // Amber for average ratings
                                      : const Color(0xFFEF4444), // Red for poor ratings
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                selectedRating >= 4
                                    ? 'Excellent'
                                    : selectedRating >= 3
                                    ? 'Good'
                                    : 'Needs improvement',
                                style: theme.bodyMedium.override(
                                  color: isDark
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF6B7280),
                                  fontSize: isSmallScreen ? 13 : 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Star buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(5, (i) {
                                  final idx = i + 1;
                                  return IconButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    onPressed: () => setState(() => selectedRating = idx),
                                    iconSize: isSmallScreen ? 32 : 38,
                                    icon: Icon(
                                      idx <= selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                                      color: idx <= selectedRating
                                          ? Colors.amber
                                          : (isDark
                                          ? const Color(0xFF4B5563)
                                          : const Color(0xFFD1D5DB)),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Review input
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add a review (optional)',
                            style: theme.bodyMedium.override(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                              fontSize: isSmallScreen ? 14 : 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF111827)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF374151)
                                    : const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            child: TextField(
                              controller: _reviewCtrl,
                              maxLines: 4,
                              minLines: 3,
                              style: theme.bodyMedium.override(
                                color: isDark ? Colors.white : const Color(0xFF111827),
                                fontSize: isSmallScreen ? 14 : 15,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Share your experience with this artisan...',
                                hintStyle: theme.bodyMedium.override(
                                  color: isDark
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFF9CA3AF),
                                  fontSize: isSmallScreen ? 13 : 14,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Inline conflict message when server responds with 409 (already reviewed)
                      if (_reviewAlreadySubmitted && _reviewConflictMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF4B2113) : const Color(0xFFFEEAE6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFF5C2BD)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: isDark ? const Color(0xFFFFD2CE) : const Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_reviewConflictMessage!, style: theme.bodyMedium.copyWith(color: isDark ? const Color(0xFFFFD2CE) : const Color(0xFF92400E)))),
                            ],
                          ),
                        ),
                      ],

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                if (Navigator.of(sheetContext).canPop()) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF6B7280),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF4B5563)
                                      : const Color(0xFFD1D5DB),
                                ),
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 14 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Skip',
                                style: theme.bodyMedium.override(
                                  fontSize: isSmallScreen ? 14 : 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (submitting || _reviewAlreadySubmitted)
                                  ? null
                                  : () async {
                                 setState(() => submitting = true);
                                 final ok = await _submitReview(selectedRating, _reviewCtrl.text.trim());
                                 setState(() => submitting = false);
                                 if (ok && Navigator.of(sheetContext).canPop()) {
                                   Navigator.of(sheetContext).pop();
                                 }
                               },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primary,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 14 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: submitting
                                  ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                                  : Text(
                                'Submit Review',
                                style: theme.bodyMedium.override(
                                  fontSize: isSmallScreen ? 14 : 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmallScreen ? 20 : 24),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Submit review to POST /api/reviews with targetId, rating, comment and optional bookingId
  Future<bool> _submitReview(int rating, String comment) async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        AppNotification.showError(context, 'Please login to submit a review');
        return false;
      }

      if (_participantId == null || _participantId!.isEmpty) {
        AppNotification.showError(context, 'No artisan found to review');
        return false;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final body = <String, dynamic>{
        'targetId': _participantId,
        'rating': rating,
      };

      if (comment.isNotEmpty) body['comment'] = comment;
      if (widget.bookingId != null && widget.bookingId!.isNotEmpty) body['bookingId'] = widget.bookingId;

      final uri = Uri.parse('$API_BASE_URL/api/reviews');
      final response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppNotification.showSuccess(context, 'Review submitted. Thank you!');
        // Clear any previous conflict state
        setState(() {
          _reviewAlreadySubmitted = false;
          _reviewConflictMessage = null;
        });
        return true;
      } else if (response.statusCode == 409) {
        print('working dupl');
        // Conflict — user already submitted a review for this target
        String serverMsg = 'You have already reviewed this artisan.';
        try {
          final parsed = response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          }
        } catch (_) {}
        // Set conflict state so the UI can show an inline message and disable submit
        setState(() {
          _reviewAlreadySubmitted = true;
          _reviewConflictMessage = serverMsg;
        });
        // Also surface a toast so user sees immediate feedback
        AppNotification.showError(context, serverMsg);
        return false;
      } else {
        String serverMsg = 'Failed to submit review';
        try {
          final parsed = response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map && (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          } else if (response.body.isNotEmpty) {
            serverMsg = response.body;
          }
        } catch (_) {}
        AppNotification.showError(context, serverMsg);
        return false;
      }
    } catch (e) {
      print(e);
      AppNotification.showError(context, 'Error submitting review: $e');
      return false;
    }
  }

  Widget _buildMarkCompleteChild() {
    if (_bookingCompleted) return const Text('Completed', style: TextStyle(fontSize: 13));
    if (_completing) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.done_all, size: 14),
        SizedBox(width: 6),
        Text('Mark Complete', style: TextStyle(fontSize: 13))
      ],
    );
  }
}


