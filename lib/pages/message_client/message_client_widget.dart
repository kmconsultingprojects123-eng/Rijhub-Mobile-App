import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../payment_webview/payment_webview_page_widget.dart';
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
  String? _currentUserImageUrl;
  String? _participantImageUrl;
  String? _participantName;
  String? _participantId;
  // whether the participant (artisan) is verified / KYCed
  bool _participantVerified = false;
  bool _waitingForThread = false;
  String? _bookingStatusFromThread;
  String? _bookingPriceFromThread;
  String? _bookingPaymentMode; // 'upfront' or 'afterCompletion'
  bool _sendingMessage = false;
  bool _bookingCompleted = false;
  bool _completing = false;
  bool _submittingReview = false;
  bool _initializingPayment = false;

  // Payment confirmation state (for afterCompletion flow)
  bool _waitingForPaymentConfirmation = false;
  bool _paymentConfirmedBySocket = false;
  Timer? _paymentConfirmationTimeout;
  String? _lastPaymentReference; // Track payment reference from WebView
  bool _paymentWebViewOpen = false;
  bool _paymentConfirmationDialogOpen = false;

  // Review conflict state: when server returns 409 (already reviewed)
  String? _reviewConflictMessage;
  bool _reviewAlreadySubmitted = false;

  // Diagnostic: last chat-related error/details to show to user for debugging
  String? _lastChatError;

  // Last known booking payment status observed while waiting for thread
  String? _lastBookingPaymentStatus;
  bool _didAttemptConfirmNudge =
      false; // avoid repeating backend nudge attempts
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
  Timer?
      _typingStoppedTimer; // local timer to send typing:false after inactivity
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
        debugPrint(
            'MessageClient(init): widget.bookingId=${widget.bookingId ?? '<null>'} widget.threadId=${widget.threadId ?? '<null>'}');
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

          // Handle payment confirmation events for afterCompletion bookings
          if (eventName == 'booking_paid' ||
              eventName == 'payment_confirmed' ||
              eventName == 'payment_success') {
            _handlePaymentConfirmed(ev);
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
      _backgroundRefreshTimer =
          Timer.periodic(const Duration(seconds: 5), (t) async {
        try {
          if (!mounted) return;
          if (_bookingCompleted) {
            _backgroundRefreshTimer?.cancel();
            return;
          }
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
      final status =
          payload is Map ? (payload['status']?.toString() ?? '') : '';

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
        if (_kDebugMode)
          debugPrint(
              'RealtimeNotifications -> thread created. threadId=$_threadId');
      } catch (_) {}
      RealtimeNotifications.instance.joinThread(tid);
      if (mounted) setState(() {});
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> ev) {
    try {
      final rawMsg = ev['message'] ?? ev['payload'] ?? ev;
      final msg = (rawMsg is Map)
          ? _normalizeMessage(Map<String, dynamic>.from(rawMsg))
          : null;

      if (msg != null) {
        // Check if this message belongs to our current thread
        final incomingTid =
            msg['threadId']?.toString() ?? msg['chatId']?.toString();
        if (incomingTid != null &&
            incomingTid.isNotEmpty &&
            (_threadId == null || incomingTid != _threadId)) {
          if (_kDebugMode)
            debugPrint(
                'Ignoring message for thread $incomingTid (current=$_threadId)');
          return;
        }

        // Check for duplicates
        if (_isDuplicateMessage(msg)) {
          if (_kDebugMode)
            debugPrint('Ignoring duplicate message: ${msg['_id']}');
          return;
        }

        if (mounted) {
          setState(() {
            _messages.add(msg);
            _loadingMessages = false;
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
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

  /// Handle payment confirmation from socket event (booking_paid, payment_confirmed, etc.)
  void _handlePaymentConfirmed(Map<String, dynamic> ev) {
    if (!_waitingForPaymentConfirmation) {
      if (_kDebugMode)
        debugPrint('Received payment confirmation but not waiting for one');
      return;
    }

    try {
      final payload = ev['payload'] ?? ev;
      final payloadMap = payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{};
      final incomingBookingId = payloadMap['bookingId']?.toString() ??
          (payloadMap['booking'] is Map
              ? (payloadMap['booking']['_id'] ?? payloadMap['booking']['id'])
                  ?.toString()
              : null);
      final reference =
          payload is Map ? payload['reference']?.toString() : null;

      if (widget.bookingId != null &&
          widget.bookingId!.isNotEmpty &&
          incomingBookingId != null &&
          incomingBookingId.isNotEmpty &&
          incomingBookingId != widget.bookingId) {
        if (_kDebugMode) {
          debugPrint(
              'Ignoring payment confirmation for different booking: $incomingBookingId');
        }
        return;
      }

      if (_lastPaymentReference != null &&
          _lastPaymentReference!.isNotEmpty &&
          reference != null &&
          reference.isNotEmpty &&
          reference != _lastPaymentReference) {
        if (_kDebugMode) {
          debugPrint(
              'Ignoring payment confirmation for different reference: $reference');
        }
        return;
      }

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: Payment confirmed via socket. Reference: $reference');
      }

      // Cancel any pending timeout
      _paymentConfirmationTimeout?.cancel();
      _paymentConfirmationTimeout = null;

      // Mark as confirmed and update state
      if (mounted) {
        setState(() {
          _paymentConfirmedBySocket = true;
          _waitingForPaymentConfirmation = false;
          if (reference != null) _lastPaymentReference = reference;
        });
      }

      if (_paymentWebViewOpen) return;

      if (mounted) {
        _closePaymentConfirmationDialogIfOpen();
        Future.delayed(const Duration(milliseconds: 200), () async {
          if (mounted && !_submittingReview) {
            // Mark booking as complete after payment confirmed via socket
            final token = await TokenStorage.getToken();
            if (token != null && token.isNotEmpty) {
              await _completeBookingAndShowRating(token);
            } else {
              await _showRatingBottomSheet();
            }
          }
        });
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error handling payment confirmation: $e');
    }
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
    _paymentConfirmationTimeout?.cancel();
    _model.textController?.removeListener(_handleTextChanged);

    try {
      RealtimeNotifications.instance.disconnect();
    } catch (_) {}

    _model.textFieldFocusNode?.removeListener(_handleFocusChange);
    _messagesScrollController.dispose();
    _model.dispose();

    // Cancel realtime subscriptions to avoid leaks / duplicate handlers
    try {
      _rnSub?.cancel();
      _rnSub = null;
    } catch (_) {}
    try {
      _rnDebugSub?.cancel();
      _rnDebugSub = null;
    } catch (_) {}
    try {
      _rnEventSub?.cancel();
      _rnEventSub = null;
    } catch (_) {}

    super.dispose();
  }

  void _handleFocusChange() {
    if (_model.textFieldFocusNode?.hasFocus ?? false) {
      // Consider user active while typing/has focus; emit online presence
      try {
        if (_currentUserId != null && _currentUserId!.isNotEmpty) {
          RealtimeNotifications.instance
              .emitPresence(_currentUserId!, 'online');
        }
      } catch (_) {}
      Future.delayed(
          const Duration(milliseconds: 200), () => _scrollToBottom());
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
      _currentUserId =
          profile?['_id']?.toString() ?? profile?['id']?.toString();
      _currentUserRole = profile?['role']?.toString();
      _currentUserImageUrl =
          profile != null ? _extractParticipantImage(profile) : null;
    } catch (_) {
      _currentUserId = null;
      _currentUserImageUrl = null;
    }

    // Emit presence online when we know our user id and socket is ready
    try {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        // ensure RealtimeNotifications is initialized first
        try {
          await RealtimeNotifications.instance.init();
        } catch (_) {}

        try {
          RealtimeNotifications.instance
              .emitPresence(_currentUserId!, 'online');
        } catch (_) {}
      }
    } catch (_) {}

    if (widget.threadId != null && widget.threadId!.isNotEmpty) {
      _threadId = widget.threadId;
      try {
        if (_kDebugMode)
          debugPrint('MessageClient: using provided threadId=${_threadId}');
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
    if (_threadId == null &&
        (widget.bookingId == null || widget.bookingId!.isEmpty)) return;

    try {
      if (_kDebugMode)
        debugPrint(
            'MessageClient: init websocket connection with threadId=${_threadId ?? '<null>'}');
    } catch (_) {}

    _wsConnecting = true;
    try {
      await RealtimeNotifications.instance.init();
      // If token and thread known, join thread so we receive realtime events
      if (_threadId != null && _threadId!.isNotEmpty) {
        RealtimeNotifications.instance.joinThread(_threadId!);
      }
    } catch (e) {
      if (_kDebugMode)
        debugPrint(
            'MessageClient: realtime init failed -> $e; falling back to polling');
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

    final bookingChanged =
        (widget.bookingId ?? '') != (oldWidget.bookingId ?? '');
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
        if (_kDebugMode)
          debugPrint(
              'MessageClient: getToken returned null — cannot fetch chat');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri =
          Uri.parse('$API_BASE_URL/api/chat/booking/${widget.bookingId}');
      if (_kDebugMode) debugPrint('MessageClient: GET $uri');

      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // Surface HTTP-level diagnostics so _waitForThreadAvailable can show exact reason
        _lastChatError =
            'Failed to fetch chat: HTTP ${resp.statusCode} ${resp.body}';
        if (_kDebugMode)
          debugPrint('MessageClient: _fetchChat non-2xx -> $_lastChatError');
        setState(() {
          _loadingMessages = false;
        });
        return;
      }

      if (_kDebugMode)
        debugPrint('MessageClient: _fetchChat resp ${resp.statusCode}');

      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
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
          if (_kDebugMode)
            debugPrint('MessageClient: _fetchChat set _threadId=$_threadId');

          // Extract participant info
          _extractParticipantInfo(Map<String, dynamic>.from(data));

          // Extract booking info
          _extractBookingInfo(Map<String, dynamic>.from(data));

          final msgs = <Map<String, dynamic>>[];
          final rawMsgs =
              (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) {
            if (m is Map) {
              msgs.add(_normalizeMessage(Map<String, dynamic>.from(m)));
            }
          }

          if (mounted) {
            setState(() {
              _messages = msgs;
              _loadingMessages = false;
            });
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToBottom());
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
      final resolvedOther = _resolveOtherParticipant(data, parts);
      if (resolvedOther != null) {
        _participantName =
            resolvedOther['name']?.toString() ?? _participantName;
        _participantImageUrl =
            resolvedOther['imageUrl']?.toString() ?? _participantImageUrl;
        _participantId = resolvedOther['id']?.toString() ?? _participantId;
      }

      // Check and set participant verification status (artisan KYC)
      _participantVerified = data['verified'] == true;
    } catch (_) {}
  }

  Map<String, String>? _resolveOtherParticipant(
    Map<String, dynamic> threadData,
    dynamic participants,
  ) {
    final candidates = <Map<String, dynamic>>[];

    if (participants is List) {
      for (final entry in participants) {
        if (entry is Map) {
          candidates.add(Map<String, dynamic>.from(entry));
        }
      }
    }

    Map<String, dynamic>? pickBestParticipant() {
      if (candidates.isEmpty) return null;

      Map<String, dynamic>? roleBasedMatch;
      Map<String, dynamic>? idBasedMatch;
      Map<String, dynamic>? firstCandidate;

      for (final candidate in candidates) {
        final pid = _extractUserId(candidate);
        final role = (candidate['role'] ?? '').toString().toLowerCase();
        firstCandidate ??= candidate;

        if (_currentUserId != null &&
            _currentUserId!.isNotEmpty &&
            pid != null &&
            pid.isNotEmpty &&
            pid != _currentUserId) {
          idBasedMatch ??= candidate;
        }

        if (_currentUserRole != null && _currentUserRole!.isNotEmpty) {
          final currentRole = _currentUserRole!.toLowerCase();
          final isOtherRole = (currentRole.contains('artisan') &&
                  (role.contains('client') || role.contains('customer'))) ||
              ((currentRole.contains('client') ||
                      currentRole.contains('customer')) &&
                  role.contains('artisan'));
          if (isOtherRole) {
            roleBasedMatch ??= candidate;
          }
        }
      }

      return roleBasedMatch ?? idBasedMatch ?? firstCandidate;
    }

    final participant = pickBestParticipant();
    if (participant != null) {
      final participantName = _extractParticipantName(participant);
      final participantImage = _extractParticipantImage(participant);
      final participantId = _extractUserId(participant);
      if ((participantName ?? '').isNotEmpty ||
          (participantImage ?? '').isNotEmpty ||
          (participantId ?? '').isNotEmpty) {
        return <String, String>{
          if (participantName != null && participantName.isNotEmpty)
            'name': participantName,
          if (participantImage != null && participantImage.isNotEmpty)
            'imageUrl': participantImage,
          if (participantId != null && participantId.isNotEmpty)
            'id': participantId,
        };
      }
    }

    final currentRole = (_currentUserRole ?? '').toLowerCase();
    final bookingNode = threadData['booking'] is Map
        ? Map<String, dynamic>.from(threadData['booking'])
        : null;
    final fallbackCustomer =
        bookingNode != null ? bookingNode['customer'] : null;
    final fallbackArtisan = bookingNode != null ? bookingNode['artisan'] : null;
    final fallbackSource = currentRole.contains('artisan')
        ? threadData['customer'] ??
            threadData['customerUser'] ??
            threadData['client'] ??
            fallbackCustomer
        : threadData['artisan'] ??
            threadData['artisanUser'] ??
            threadData['artisanProfile'] ??
            fallbackArtisan;

    if (fallbackSource is Map) {
      final fallback = Map<String, dynamic>.from(fallbackSource);
      final fallbackName = _extractParticipantName(fallback);
      final fallbackImage = _extractParticipantImage(fallback);
      final fallbackId = _extractUserId(fallback);
      if ((fallbackName ?? '').isNotEmpty ||
          (fallbackImage ?? '').isNotEmpty ||
          (fallbackId ?? '').isNotEmpty) {
        return <String, String>{
          if (fallbackName != null && fallbackName.isNotEmpty)
            'name': fallbackName,
          if (fallbackImage != null && fallbackImage.isNotEmpty)
            'imageUrl': fallbackImage,
          if (fallbackId != null && fallbackId.isNotEmpty) 'id': fallbackId,
        };
      }
    }

    return null;
  }

  String? _extractUserId(Map<String, dynamic> data) {
    for (final key in ['_id', 'id', 'userId', 'participantId']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    final nestedUser = data['user'];
    if (nestedUser is Map) {
      return _extractUserId(Map<String, dynamic>.from(nestedUser));
    }
    return null;
  }

  String? _extractParticipantName(Map<String, dynamic> data) {
    for (final key in ['name', 'fullName', 'displayName', 'businessName']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final nestedUser = data['user'];
    if (nestedUser is Map) {
      return _extractParticipantName(Map<String, dynamic>.from(nestedUser));
    }
    return null;
  }

  String? _extractParticipantImage(Map<String, dynamic> data) {
    final directCandidates = [
      data['profileImageUrl'],
      data['senderImageUrl'],
      data['profileImage'],
      data['avatar'],
      data['image'],
      data['photo'],
      data['picture'],
    ];
    for (final candidate in directCandidates) {
      final normalized = _normalizeImageUrl(candidate);
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }

    final nestedCandidates = [
      data['user'],
      data['profile'],
      data['artisanAuthDetails'],
    ];
    for (final candidate in nestedCandidates) {
      if (candidate is Map) {
        final normalized =
            _extractParticipantImage(Map<String, dynamic>.from(candidate));
        if (normalized != null && normalized.isNotEmpty) {
          return normalized;
        }
      }
    }

    return null;
  }

  String? _extractImageUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.trim().isEmpty ? null : value;
    if (value is Map) {
      for (final key in [
        'url',
        'secure_url',
        'secureUrl',
        'path',
        'src',
        'imageUrl',
        'image_url',
      ]) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }
    return null;
  }

  String? _normalizeImageUrl(dynamic value) {
    final raw = _extractImageUrl(value);
    if (raw == null || raw.trim().isEmpty) return null;
    if (raw.startsWith('//')) return 'https:$raw';
    return raw.trim();
  }

  Widget _buildProfileAvatar({
    required String? imageUrl,
    required double radius,
    required Color backgroundColor,
    required Color iconColor,
    required double iconSize,
  }) {
    final normalizedUrl = _normalizeImageUrl(imageUrl);
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: Icon(Icons.person, color: iconColor, size: iconSize),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: normalizedUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: radius * 2,
          height: radius * 2,
          color: backgroundColor,
          alignment: Alignment.center,
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
            ),
          ),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          child: Icon(Icons.person, color: iconColor, size: iconSize),
        ),
        imageBuilder: (context, imageProvider) => Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  void _extractBookingInfo(Map<String, dynamic> data) {
    try {
      final bookingMeta =
          data['booking'] ?? data['bookingInfo'] ?? data['bookingMeta'];
      if (bookingMeta is Map) {
        _bookingStatusFromThread =
            bookingMeta['status']?.toString() ?? _bookingStatusFromThread;
        _bookingPaymentMode =
            bookingMeta['paymentMode']?.toString() ?? _bookingPaymentMode;
        final priceVal = bookingMeta['price'] ??
            bookingMeta['amount'] ??
            bookingMeta['total'];
        if (priceVal != null) {
          if (priceVal is num) {
            _bookingPriceFromThread =
                '₦' + NumberFormat('#,##0', 'en_US').format(priceVal);
          } else {
            final s = priceVal.toString();
            final n = num.tryParse(s.replaceAll(RegExp(r'[^0-9.-]'), ''));
            if (n != null) {
              _bookingPriceFromThread =
                  '₦' + NumberFormat('#,##0', 'en_US').format(n);
            } else {
              _bookingPriceFromThread = s;
            }
          }
        }
      }
    } catch (_) {}
  }

  bool _isAfterCompletionMode(String? mode) {
    return (mode ?? '').trim().toLowerCase() == 'aftercompletion';
  }

  bool _isCompletedBookingStatus(String? status) {
    return (status ?? '').trim().toLowerCase() == 'completed';
  }

  bool _serverRequiresPaymentInitializationBeforeCompletion(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    return normalized.contains(
            'payment must be initialize before marking work completed') ||
        normalized.contains(
            'payment must be initialized before marking work completed') ||
        normalized.contains('initialize payment before marking work completed');
  }

  int? _parseAmountValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.round();
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned)?.round();
  }

  Future<String?> _refreshBookingPaymentMode({String? token}) async {
    if (widget.bookingId == null || widget.bookingId!.isEmpty)
      return _bookingPaymentMode;

    try {
      final authToken = token ?? await TokenStorage.getToken();
      if (authToken == null || authToken.isEmpty) return _bookingPaymentMode;

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken'
      };

      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.isNotEmpty) {
        final parsed = jsonDecode(response.body);
        final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
        final booking = data is Map ? (data['booking'] ?? data) : null;

        if (booking is Map) {
          final paymentMode = booking['paymentMode']?.toString();
          final bookingStatus = booking['status']?.toString();
          if (mounted) {
            setState(() {
              _bookingPaymentMode = paymentMode ?? _bookingPaymentMode;
              _bookingStatusFromThread =
                  bookingStatus ?? _bookingStatusFromThread;
            });
          } else {
            _bookingPaymentMode = paymentMode ?? _bookingPaymentMode;
            _bookingStatusFromThread =
                bookingStatus ?? _bookingStatusFromThread;
          }
          return paymentMode ?? _bookingPaymentMode;
        }
      }
    } catch (e) {
      if (_kDebugMode)
        debugPrint('MessageClient: failed to refresh booking payment mode: $e');
    }

    return _bookingPaymentMode;
  }

  Future<bool> _waitForBookingCompletedStatus(
    String token, {
    int maxAttempts = 8,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    if (widget.bookingId == null || widget.bookingId!.isEmpty) return false;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };

    final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.body.isNotEmpty) {
          final parsed = jsonDecode(response.body);
          final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
          final booking = data is Map ? (data['booking'] ?? data) : null;
          final status = booking is Map ? booking['status']?.toString() : null;

          if (_kDebugMode) {
            debugPrint(
              'MessageClient: booking completion poll attempt ${attempt + 1}/$maxAttempts status=$status',
            );
          }

          if (_isCompletedBookingStatus(status)) {
            if (mounted) {
              setState(() {
                _bookingCompleted = true;
                _bookingStatusFromThread = status;
              });
            } else {
              _bookingCompleted = true;
              _bookingStatusFromThread = status;
            }
            return true;
          }
        }
      } catch (e) {
        if (_kDebugMode) {
          debugPrint(
            'MessageClient: booking completion poll attempt ${attempt + 1} failed: $e',
          );
        }
      }

      if (attempt < maxAttempts - 1) {
        await Future.delayed(delay);
      }
    }

    return _isCompletedBookingStatus(_bookingStatusFromThread) ||
        _bookingCompleted;
  }

  Future<int?> _resolveBookingAmountForDeferredPayment(String token) async {
    final localCandidates = <dynamic>[
      _bookingPriceFromThread,
      widget.bookingPrice,
    ];
    for (final candidate in localCandidates) {
      final amount = _parseAmountValue(candidate);
      if (amount != null && amount > 0) return amount;
    }

    if (widget.bookingId == null || widget.bookingId!.isEmpty) return null;

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };
      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.isNotEmpty) {
        final parsed = jsonDecode(response.body);
        final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
        final booking = data is Map ? (data['booking'] ?? data) : null;

        if (booking is Map) {
          final amount = _parseAmountValue(
            booking['clientTotal'] ??
                booking['price'] ??
                booking['amount'] ??
                booking['total'],
          );
          final status = booking['status']?.toString();

          if (status != null) {
            if (mounted) {
              setState(() {
                _bookingStatusFromThread = status;
              });
            } else {
              _bookingStatusFromThread = status;
            }
          }

          if (amount != null && amount > 0) return amount;
        }
      }
    } catch (e) {
      if (_kDebugMode) {
        debugPrint(
            'MessageClient: failed to resolve booking amount for deferred payment: $e');
      }
    }

    return null;
  }

  Future<void> _initializeDeferredPaymentBeforeCompletion(String token) async {
    try {
      if (mounted) setState(() => _initializingPayment = true);

      if (widget.bookingId == null || widget.bookingId!.isEmpty) {
        AppNotification.showError(context, 'No booking selected');
        return;
      }

      final amount = await _resolveBookingAmountForDeferredPayment(token);
      if (amount == null || amount <= 0) {
        AppNotification.showError(
            context, 'Unable to determine the booking amount for payment.');
        return;
      }

      String? customerEmail;
      try {
        final profile = await UserService.getProfile();
        customerEmail = profile?['email']?.toString();
      } catch (_) {}

      if (customerEmail == null || customerEmail.isEmpty) {
        AppNotification.showError(
            context, 'Unable to retrieve your email for payment');
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri = Uri.parse('$API_BASE_URL/api/payments/initialize');
      final payload = <String, dynamic>{
        'amount': amount,
        'currency': 'NGN',
        'email': customerEmail,
        'type': 'booking',
        'bookingSource': 'booking',
        'bookingId': widget.bookingId,
        'metadata': {
          'bookingId': widget.bookingId,
          'paymentMode': 'afterCompletion',
          if (widget.jobTitle != null && widget.jobTitle!.trim().isNotEmpty)
            'service': widget.jobTitle!.trim(),
        },
      };

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: Initializing generic deferred payment before completion POST $uri');
      }

      final response = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (_kDebugMode) {
        debugPrint(
          'MessageClient: generic deferred payment init response ${response.statusCode} ${response.body}',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = jsonDecode(response.body);
        final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
        final authUrl =
            data is Map ? data['authorization_url']?.toString() : null;
        final paymentReference =
            data is Map ? data['reference']?.toString() : null;

        if (authUrl != null && authUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _waitingForPaymentConfirmation = true;
              _paymentConfirmedBySocket = false;
              _lastPaymentReference = paymentReference;
            });
          }
          await _handlePaymentWebView(authUrl, paymentReference);
          return;
        }

        AppNotification.showError(
          context,
          'Payment initialization succeeded but no checkout URL was returned.',
        );
        return;
      }

      String serverMsg = 'Failed to initialize payment';
      try {
        final parsed =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        if (parsed is Map &&
            (parsed['message'] != null || parsed['error'] != null)) {
          serverMsg = (parsed['message'] ?? parsed['error']).toString();
        } else if (response.body.isNotEmpty) {
          serverMsg = response.body;
        }
      } catch (_) {}
      AppNotification.showError(context, serverMsg);
    } catch (e) {
      if (_kDebugMode)
        debugPrint('Error initializing payment before completion: $e');
      AppNotification.showError(context, 'Error initializing payment: $e');
    } finally {
      if (mounted) setState(() => _initializingPayment = false);
    }
  }

  void _closePaymentConfirmationDialogIfOpen() {
    if (!_paymentConfirmationDialogOpen || !mounted) return;
    _paymentConfirmationDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<bool> _verifyPaymentReference(String reference) async {
    if (reference.trim().isEmpty) return false;

    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final uri = Uri.parse('$API_BASE_URL/api/payments/verify');
      final payload = <String, dynamic>{'reference': reference};

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: verifying payment reference $reference via $uri');
      }

      final response = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: payment verify response ${response.statusCode} ${response.body}');
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.body.isEmpty) {
        return false;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map &&
          (decoded['success'] == true || decoded['ok'] == true)) {
        return true;
      }

      final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (data is Map) {
        final statusRaw = data['status'] ??
            data['paymentStatus'] ??
            data['paid'] ??
            data['isPaid'] ??
            data['state'] ??
            data['statusText'];

        if (statusRaw is bool) return statusRaw;
        final statusText = statusRaw?.toString().toLowerCase() ?? '';
        const okValues = <String>[
          'paid',
          'success',
          'completed',
          'held',
          'holding',
          'authorized',
          'successful',
          'ok',
        ];
        for (final value in okValues) {
          if (statusText.contains(value)) return true;
        }

        final paymentNode = data['payment'] ??
            data['paymentData'] ??
            data['payment_response'] ??
            data['authorization'];
        if (paymentNode is Map) {
          final paymentStatus = paymentNode['status'] ??
              paymentNode['paid'] ??
              paymentNode['isPaid'] ??
              paymentNode['paymentStatus'];
          if (paymentStatus is bool) return paymentStatus;
          final paymentText = paymentStatus?.toString().toLowerCase() ?? '';
          for (final value in okValues) {
            if (paymentText.contains(value)) return true;
          }
        }
      }
    } catch (e) {
      if (_kDebugMode)
        debugPrint('MessageClient: verify payment reference error: $e');
    }

    return false;
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
        if (_kDebugMode)
          debugPrint(
              'MessageClient: getToken returned null — cannot fetch chat by thread');
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

      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _lastChatError =
            'Failed to fetch chat by thread: HTTP ${resp.statusCode} ${resp.body}';
        if (_kDebugMode)
          debugPrint(
              'MessageClient: _fetchChatByThreadId non-2xx -> $_lastChatError');
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
        final rawMsgs =
            (data['messages'] is List) ? data['messages'] as List : [];
        for (final m in rawMsgs) {
          if (m is Map) {
            msgs.add(_normalizeMessage(Map<String, dynamic>.from(m)));
          }
        }

        if (mounted) {
          setState(() {
            _messages = msgs;
            _loadingMessages = false;
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }
        return;
      }

      setState(() {
        _messages = [];
        _loadingMessages = false;
      });
    } catch (e) {
      if (_kDebugMode)
        debugPrint('MessageClient: _fetchChatByThreadId exception: $e');
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  // Silent background fetch that updates messages without toggling loading UI
  Future<void> _fetchChatByThreadIdInBackground() async {
    try {
      if (_threadId == null || _threadId!.isEmpty) return;
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };
      final uri = Uri.parse('$API_BASE_URL/api/chat/${_threadId}');
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        final data = body is Map ? (body['data'] ?? body) : body;
        if (data is Map) {
          _extractParticipantInfo(Map<String, dynamic>.from(data));
          final msgs = <Map<String, dynamic>>[];
          final rawMsgs =
              (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) {
            if (m is Map) {
              msgs.add(_normalizeMessage(Map<String, dynamic>.from(m)));
            }
          }
          if (!mounted) return;
          setState(() {
            _messages = msgs;
            // don't change _loadingMessages here so UI isn't affected
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };
      final uri =
          Uri.parse('$API_BASE_URL/api/chat/booking/${widget.bookingId}');
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body);
        final data = body is Map ? (body['data'] ?? body) : body;
        if (data is Map) {
          final msgs = <Map<String, dynamic>>[];
          final rawMsgs =
              (data['messages'] is List) ? data['messages'] as List : [];
          for (final m in rawMsgs) {
            if (m is Map) {
              msgs.add(_normalizeMessage(Map<String, dynamic>.from(m)));
            }
          }
          if (!mounted) return;
          // Update threadId/participant info silently as well
          try {
            _threadId = data['threadId']?.toString() ??
                data['_id']?.toString() ??
                _threadId;
          } catch (_) {}
          try {
            _extractParticipantInfo(Map<String, dynamic>.from(data));
          } catch (_) {}
          try {
            _extractBookingInfo(Map<String, dynamic>.from(data));
          } catch (_) {}
          setState(() {
            _messages = msgs;
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Background _fetchChat error: $e');
    }
  }

  Future<void> _notifyMessageSent(String text) async {
    try {
      // Prefer to send chat messages over the socket if connected and threadId is known.
      if (RealtimeNotifications.instance.connected &&
          _threadId != null &&
          _threadId!.isNotEmpty) {
        try {
          // Ensure socket is ready
          if (!RealtimeNotifications.instance.connected) {
            await RealtimeNotifications.instance.init();
          }

          // Use the sendChatMessage method (fire-and-forget: method is void)
          RealtimeNotifications.instance.sendChatMessage(_threadId!, text);
          if (_kDebugMode)
            debugPrint(
                'notifyMessageSent: sent via socket for thread=$_threadId');
          return;
        } catch (e) {
          if (_kDebugMode)
            debugPrint('notifyMessageSent socket send error: $e');
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
      if (_kDebugMode)
        debugPrint('notifyMessageSent: emitted notification fallback');
    } catch (e) {
      if (_kDebugMode) debugPrint('notifyMessageSent error: $e');
    }
  }

  Future<bool> _waitForThreadAvailable(
      {int attempts = 3, Duration delay = const Duration(seconds: 1)}) async {
    if (widget.bookingId == null || widget.bookingId!.isEmpty) return false;

    try {
      for (int i = 0; i < attempts; i++) {
        if (_kDebugMode)
          debugPrint(
              'MessageClient: waitForThreadAvailable attempt ${i + 1}/${attempts} currentThreadId=${_threadId}');

        // If we already have a thread, we're done
        if (_threadId != null && _threadId!.isNotEmpty) return true;

        // Fetch latest chat info which will set _threadId if created
        await _fetchChat();
        if (_kDebugMode)
          debugPrint(
              'MessageClient: after _fetchChat threadId=${_threadId} lastChatError=${_lastChatError}');

        if (_threadId != null && _threadId!.isNotEmpty) return true;

        // If we got a 404 "Thread not found" but booking is paid, try nudging the backend once
        if (!_didAttemptConfirmNudge &&
            _lastChatError != null &&
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
      final resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        final parsed = jsonDecode(resp.body);
        final booking = parsed is Map ? (parsed['data'] ?? parsed) : parsed;

        if (booking is Map) {
          final payStatus =
              (booking['paymentStatus'] ?? booking['payment'] ?? '')
                  .toString()
                  .toLowerCase();
          _lastBookingPaymentStatus = payStatus;

          if (payStatus == 'paid') {
            // Attempt to nudge backend to create/confirm booking resources (idempotent)
            try {
              final confirmUri = Uri.parse(
                  '$API_BASE_URL/api/bookings/${widget.bookingId}/confirm-payment');
              if (_kDebugMode)
                debugPrint(
                    'MessageClient: nudging backend confirm-payment $confirmUri');

              final nresp = await http
                  .post(confirmUri, headers: headers)
                  .timeout(const Duration(seconds: 8));
              if (_kDebugMode)
                debugPrint(
                    'MessageClient: confirm nudge resp ${nresp.statusCode} ${nresp.body}');
            } catch (e) {
              if (_kDebugMode)
                debugPrint('MessageClient: confirm nudge failed: $e');
            }
            _didAttemptConfirmNudge = true;
          } else {
            // booking not paid yet — chat won't exist until webhook runs
            if (_kDebugMode)
              debugPrint('Chat not ready: booking paymentStatus=$payStatus');
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

        final got = await _waitForThreadAvailable(
            attempts: 4, delay: const Duration(seconds: 1));

        // hide preparing snackbar
        scaffold.hideCurrentSnackBar();
        setState(() => _waitingForThread = false);

        if (!got) {
          final err =
              _lastChatError ?? 'Unable to send message — chat not ready.';
          final composed =
              '$err\n\nContext: bookingId=${widget.bookingId ?? 'null'} threadId=${_threadId ?? 'null'} lastBookingPaymentStatus=${_lastBookingPaymentStatus ?? 'unknown'}';
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

      final got = await _waitForThreadAvailable(
          attempts: 4, delay: const Duration(seconds: 1));
      scaffold.hideCurrentSnackBar();
      setState(() => _waitingForThread = false);

      if (!got) {
        final err =
            _lastChatError ?? 'Unable to send message — chat not ready.';
        final composed =
            '$err\n\nContext: bookingId=${widget.bookingId ?? 'null'} threadId=${_threadId ?? 'null'} lastBookingPaymentStatus=${_lastBookingPaymentStatus ?? 'unknown'}';
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
      debugPrint(
          'Socket connected: ${RealtimeNotifications.instance.connected}');
    }

    try {
      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (_kDebugMode)
        debugPrint('MessageClient: send resp ${resp.statusCode} ${resp.body}');

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
              if (saved is Map &&
                  saved['message'] != null &&
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
            msgObj = _normalizeMessage(Map<String, dynamic>.from(saved));
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

          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());

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
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
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
      final incomingText =
          msg['text']?.toString() ?? msg['message']?.toString();
      final incomingTime =
          msg['createdAt']?.toString() ?? msg['timestamp']?.toString();

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
    final messageMaxWidth =
        screenWidth < 400 ? screenWidth * 0.75 : screenWidth * 0.7;

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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
        final m = _normalizeMessage(_messages[i]);
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
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _buildProfileAvatar(
                        imageUrl: _resolveMessageAvatarUrl(m, isMe: isMe),
                        radius: screenWidth < 360 ? 14 : 18,
                        backgroundColor: theme.alternate,
                        iconColor: theme.secondaryText,
                        iconSize: screenWidth < 360 ? 14 : 18,
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
                              color: isMe ? Colors.white : theme.primaryText,
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
                      child: _buildProfileAvatar(
                        imageUrl: _resolveMessageAvatarUrl(m, isMe: isMe),
                        radius: screenWidth < 360 ? 14 : 18,
                        backgroundColor: theme.primary.withOpacity(0.1),
                        iconColor: theme.primary,
                        iconSize: screenWidth < 360 ? 14 : 18,
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

  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> message) {
    final normalized = Map<String, dynamic>.from(message);
    final senderId = normalized['senderId']?.toString() ??
        normalized['sender']?['_id']?.toString() ??
        normalized['sender']?['id']?.toString();

    if ((normalized['senderName'] == null ||
            normalized['senderName'].toString().trim().isEmpty) &&
        normalized['sender'] is Map) {
      normalized['senderName'] = _extractParticipantName(
        Map<String, dynamic>.from(normalized['sender']),
      );
    }

    final existingSenderImage = _normalizeImageUrl(
        normalized['senderImageUrl'] ?? normalized['avatar']);
    if (existingSenderImage != null && existingSenderImage.isNotEmpty) {
      normalized['senderImageUrl'] = existingSenderImage;
    } else if (normalized['sender'] is Map) {
      final nestedImage = _extractParticipantImage(
        Map<String, dynamic>.from(normalized['sender']),
      );
      if (nestedImage != null && nestedImage.isNotEmpty) {
        normalized['senderImageUrl'] = nestedImage;
      }
    }

    final isOtherParticipant = senderId != null &&
        senderId.isNotEmpty &&
        _participantId != null &&
        _participantId!.isNotEmpty &&
        senderId == _participantId;
    if ((normalized['senderImageUrl'] == null ||
            normalized['senderImageUrl'].toString().trim().isEmpty) &&
        isOtherParticipant &&
        _participantImageUrl != null &&
        _participantImageUrl!.isNotEmpty) {
      normalized['senderImageUrl'] = _participantImageUrl;
    } else if ((normalized['senderImageUrl'] == null ||
            normalized['senderImageUrl'].toString().trim().isEmpty) &&
        senderId != null &&
        senderId.isNotEmpty &&
        _currentUserId != null &&
        _currentUserId!.isNotEmpty &&
        senderId == _currentUserId &&
        _currentUserImageUrl != null &&
        _currentUserImageUrl!.isNotEmpty) {
      normalized['senderImageUrl'] = _currentUserImageUrl;
    }

    return normalized;
  }

  String? _resolveMessageAvatarUrl(
    Map<String, dynamic> message, {
    required bool isMe,
  }) {
    final direct = _normalizeImageUrl(message['senderImageUrl']);
    if (direct != null && direct.isNotEmpty) return direct;

    final sender = message['sender'];
    if (sender is Map) {
      final nested =
          _extractParticipantImage(Map<String, dynamic>.from(sender));
      if (nested != null && nested.isNotEmpty) return nested;
    }

    if (isMe &&
        _currentUserImageUrl != null &&
        _currentUserImageUrl!.isNotEmpty) {
      return _currentUserImageUrl;
    }

    if (isMe) return null;

    return _participantImageUrl;
  }

  Widget _buildSendingMessage(
      Map<String, dynamic> m, FlutterFlowTheme theme, double screenWidth) {
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
                maxWidth:
                    screenWidth < 400 ? screenWidth * 0.75 : screenWidth * 0.7,
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

    final appBarTitle =
        (widget.jobTitle != null && widget.jobTitle!.trim().isNotEmpty)
            ? widget.jobTitle!.trim()
            : ((_participantName != null && _participantName!.trim().isNotEmpty)
                ? _participantName!.trim()
                : 'Chat');
    final appBarMeta = <String>[
      if (_participantName != null &&
          _participantName!.trim().isNotEmpty &&
          _participantName!.trim() != appBarTitle)
        _participantName!.trim(),
      if ((_bookingPriceFromThread ?? widget.bookingPrice) != null &&
          (_bookingPriceFromThread ?? widget.bookingPrice)!
              .toString()
              .trim()
              .isNotEmpty)
        (_bookingPriceFromThread ?? widget.bookingPrice)!.toString().trim(),
      if (widget.bookingDateTime != null &&
          widget.bookingDateTime!.trim().isNotEmpty)
        widget.bookingDateTime!.trim(),
      if (_bookingStatusFromThread != null &&
          _bookingStatusFromThread!.trim().isNotEmpty)
        _bookingStatusFromThread!.trim(),
    ];

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
              Stack(
                children: [
                  _buildProfileAvatar(
                    imageUrl: _participantImageUrl,
                    radius: isSmallScreen ? 16 : 20,
                    backgroundColor: theme.alternate,
                    iconColor: theme.secondaryText,
                    iconSize: isSmallScreen ? 16 : 20,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _peerOnline ? theme.success : theme.alternate,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.primaryBackground,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: isSmallScreen ? 8 : 12.0),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appBarTitle,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium.override(
                        fontFamily: 'Inter',
                        fontSize: isSmallScreen ? 14.0 : 16.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (appBarMeta.isNotEmpty)
                      Text(
                        appBarMeta.join(' • '),
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
                tooltip: _lastRealtimeEvent != null
                    ? 'Last event: $_lastRealtimeEvent'
                    : 'Realtime status',
                icon: Icon(
                  RealtimeNotifications.instance.connected || _socketConnected
                      ? Icons.wifi_rounded
                      : Icons.wifi_off_rounded,
                  color: RealtimeNotifications.instance.connected ||
                          _socketConnected
                      ? theme.success
                      : theme.secondaryText,
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
                      _socketConnected =
                          RealtimeNotifications.instance.connected;
                    });
                    final snack = ScaffoldMessenger.of(context);
                    snack.showSnackBar(SnackBar(
                        content: Text(
                            'Realtime: ${RealtimeNotifications.instance.connected ? 'connected' : 'disconnected'}')));
                  } catch (e) {
                    if (_kDebugMode) debugPrint('Manual reconnect failed: $e');
                    final snack = ScaffoldMessenger.of(context);
                    snack.showSnackBar(SnackBar(
                        content: Text('Realtime reconnect failed: $e')));
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
                      _bookingCompleted
                          ? Icons.check_circle_outline
                          : Icons.check_circle,
                      color: _bookingCompleted
                          ? theme.secondaryText
                          : theme.success,
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
                          color: _bookingCompleted
                              ? theme.secondaryText
                              : theme.success,
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
                                  if (mounted)
                                    setState(() => _completing = false);
                                },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _bookingCompleted
                                ? theme.alternate.withOpacity(0.3)
                                : theme.primary,
                            foregroundColor: _bookingCompleted
                                ? theme.secondaryText
                                : Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 12 : 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  isSmallScreen ? 10 : 12),
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
                              borderRadius: BorderRadius.circular(
                                  isSmallScreen ? 20 : 24.0),
                              border: Border.all(
                                  color: theme.alternate.withOpacity(0.2)),
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
                                  color: _bookingCompleted
                                      ? theme.error
                                      : theme.secondaryText,
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
                              validator: _model.textControllerValidator
                                  .asValidator(context),
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
                                    (_model.textController?.text
                                            .trim()
                                            .isEmpty ??
                                        true) ||
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Icon(
                                    Icons.send_rounded,
                                    color: (!_sendButtonEnabled ||
                                            _sendingMessage ||
                                            _waitingForThread ||
                                            (_model.textController?.text
                                                    .trim()
                                                    .isEmpty ??
                                                true) ||
                                            _bookingCompleted)
                                        ? theme.secondaryText
                                        : Colors.white,
                                    size: isSmallScreen ? 18 : 20.0,
                                  ),
                            onPressed: (!_sendButtonEnabled ||
                                    _sendingMessage ||
                                    _waitingForThread ||
                                    (_model.textController?.text
                                            .trim()
                                            .isEmpty ??
                                        true) ||
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
                    scaffold.showSnackBar(const SnackBar(
                        content: Text('Error details copied to clipboard.')));
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

      final resolvedPaymentMode =
          await _refreshBookingPaymentMode(token: token);

      // For after-completion payments: initialize payment first. The booking should only
      // be marked complete after payment succeeds.
      if (_isAfterCompletionMode(resolvedPaymentMode)) {
        if (_kDebugMode) {
          debugPrint(
              'MessageClient: After-completion payment mode detected. Initializing generic payment before completion...');
        }
        try {
          if (mounted) await Future.delayed(const Duration(milliseconds: 200));
          await _initializeDeferredPaymentBeforeCompletion(token);
        } catch (e) {
          if (_kDebugMode)
            debugPrint(
                'Error initializing generic payment before completion: $e');
          AppNotification.showError(
            context,
            'Unable to initialize payment. Please try again.',
          );
        }
      } else {
        // For upfront payments: Mark complete immediately, then show rating
        if (_kDebugMode) {
          debugPrint(
              'MessageClient: Upfront payment mode. Marking booking as complete...');
        }
        await _completeBookingAndShowRating(token);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error in _markJobComplete: $e');
      AppNotification.showError(context, 'Error: $e');
    }
  }

  /// Complete booking and show rating sheet for upfront payments
  Future<void> _completeBookingAndShowRating(String token) async {
    try {
      // If booking is already marked completed (e.g., UI completed it before payment),
      // skip the API call and directly show the rating sheet.
      if (_bookingCompleted) {
        try {
          if (mounted) await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) await _showRatingBottomSheet();
        } catch (_) {}
        return;
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri =
          Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}/complete');
      final payload = jsonEncode({'sendEmail': true});
      final response = await http
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppNotification.showSuccess(context, 'Booking marked as completed');
        if (mounted) {
          setState(() {
            _bookingCompleted = true;
          });
        }

        // Show rating immediately for upfront payments
        try {
          if (mounted) await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) await _showRatingBottomSheet();
        } catch (_) {}
      } else {
        // Try to extract error message from response
        String serverMsg = 'Failed to mark booking as complete';
        try {
          final parsed =
              response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          } else if (response.body.isNotEmpty) {
            serverMsg = response.body;
          }
        } catch (_) {}
        AppNotification.showError(context, serverMsg);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error completing booking: $e');
      AppNotification.showError(context, 'Error marking booking complete: $e');
    }
  }

  /// Complete booking on server and then initialize deferred payment flow.
  /// This is used for backends that require the booking to be completed before
  /// `pay-after-completion` is allowed.
  Future<void> _completeBookingThenInitPayment(String token) async {
    try {
      if (_bookingCompleted ||
          _isCompletedBookingStatus(_bookingStatusFromThread)) {
        final completed =
            await _waitForBookingCompletedStatus(token, maxAttempts: 2);
        if (!completed) {
          AppNotification.showError(
            context,
            'Booking status is still syncing. Please try payment again in a moment.',
          );
          return;
        }

        if (mounted) await _initializeDeferredPayment();
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      final uri =
          Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}/complete');
      final payload = jsonEncode({'sendEmail': true});
      final response = await http
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppNotification.showSuccess(context, 'Booking marked as completed');
        if (mounted) {
          setState(() {
            _bookingCompleted = true;
          });
        }

        final completed = await _waitForBookingCompletedStatus(token);
        if (!completed) {
          AppNotification.showError(
            context,
            'Booking completion is still syncing. Please try payment again in a moment.',
          );
          return;
        }

        // After the completed status is observable, initialize deferred payment.
        try {
          if (mounted) await _initializeDeferredPayment();
        } catch (e) {
          if (_kDebugMode)
            debugPrint(
                'Error initializing deferred payment after completion: $e');
          AppNotification.showError(
              context, 'Unable to initialize payment after completion.');
        }
      } else {
        String serverMsg = 'Failed to mark booking as complete';
        try {
          final parsed =
              response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          } else if (response.body.isNotEmpty) {
            serverMsg = response.body;
          }
        } catch (_) {}
        if (_serverRequiresPaymentInitializationBeforeCompletion(serverMsg)) {
          await _initializeDeferredPaymentBeforeCompletion(token);
          return;
        }
        AppNotification.showError(context, serverMsg);
      }
    } catch (e) {
      if (_kDebugMode)
        debugPrint('Error completing booking then initializing payment: $e');
      AppNotification.showError(context, 'Error: $e');
    }
  }

  /// Initialize deferred payment for afterCompletion bookings
  /// Calls POST /booking/:id/pay-after-completion
  /// Navigates to WebView for secure payment and waits for confirmation
  Future<void> _initializeDeferredPayment() async {
    try {
      setState(() => _initializingPayment = true);

      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        AppNotification.showError(
            context, 'Please login to proceed with payment');
        setState(() => _initializingPayment = false);
        return;
      }

      if (widget.bookingId == null || widget.bookingId!.isEmpty) {
        AppNotification.showError(context, 'No booking selected');
        setState(() => _initializingPayment = false);
        return;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      // Get user profile for email
      String? customerEmail;
      try {
        final profile = await UserService.getProfile();
        customerEmail = profile?['email']?.toString();
      } catch (_) {}

      if (customerEmail == null || customerEmail.isEmpty) {
        AppNotification.showError(
            context, 'Unable to retrieve your email for payment');
        setState(() => _initializingPayment = false);
        return;
      }

      final uri = Uri.parse(
          '$API_BASE_URL/api/bookings/${widget.bookingId}/pay-after-completion');
      final payload = jsonEncode({
        'email': customerEmail,
        'customerCoords': {'lat': 0.0, 'lon': 0.0}
      });

      if (_kDebugMode)
        debugPrint('MessageClient: Initializing deferred payment POST $uri');

      final response = await http
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 15));

      if (_kDebugMode)
        debugPrint(
            'MessageClient: deferred payment init response ${response.statusCode} ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final parsed = jsonDecode(response.body);
          final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;

          if (data is Map) {
            final payment = data['payment'];
            final authUrl = payment is Map
                ? (payment['authorization_url'] ?? payment['authorizationUrl'])
                : null;
            final paymentReference = payment is Map
                ? (payment['reference'] ?? payment['paymentReference'])
                    ?.toString()
                : null;

            if (authUrl != null && authUrl.toString().isNotEmpty) {
              if (mounted) {
                setState(() {
                  _waitingForPaymentConfirmation = true;
                  _paymentConfirmedBySocket = false;
                  _lastPaymentReference = paymentReference;
                });
              }

              if (mounted) {
                await _handlePaymentWebView(
                    authUrl.toString(), paymentReference);
              }
            } else {
              AppNotification.showError(
                context,
                'Payment initialization succeeded but no checkout URL was returned.',
              );
            }
          }
        } catch (e) {
          if (_kDebugMode) debugPrint('Error parsing payment response: $e');
          AppNotification.showError(
            context,
            'Payment initialization response could not be processed.',
          );
        }
      } else {
        String serverMsg = 'Failed to initialize payment';
        try {
          final parsed =
              response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
            serverMsg = (parsed['message'] ?? parsed['error']).toString();
          } else if (response.body.isNotEmpty) {
            serverMsg = response.body;
          }
        } catch (_) {}
        AppNotification.showError(context, serverMsg);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error initializing deferred payment: $e');
      AppNotification.showError(context, 'Error initializing payment: $e');
    } finally {
      if (mounted) setState(() => _initializingPayment = false);
    }
  }

  /// Handle payment via WebView and wait for confirmation
  /// Navigates to PaymentWebviewPageWidget and handles the result
  Future<void> _handlePaymentWebView(
      String authUrl, String? expectedReference) async {
    try {
      if (!mounted) return;

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: Navigating to payment WebView with URL: $authUrl');
      }

      _paymentWebViewOpen = true;

      // Navigate to payment WebView and await result
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => PaymentWebviewPageWidget(
            url: authUrl,
            expectedReference: expectedReference,
          ),
          fullscreenDialog: true,
        ),
      );

      _paymentWebViewOpen = false;

      if (!mounted) return;

      if (_kDebugMode) {
        debugPrint('MessageClient: WebView returned result: $result');
      }

      // Check if payment was successful
      final success = result?['success'] ?? false;

      if (success) {
        final returnedReference = result?['reference']?.toString();
        if (returnedReference != null && returnedReference.isNotEmpty) {
          _lastPaymentReference = returnedReference;
        }

        final referenceToVerify = _lastPaymentReference ?? expectedReference;
        if (referenceToVerify != null && referenceToVerify.isNotEmpty) {
          final verified = await _verifyPaymentReference(referenceToVerify);
          if (verified) {
            if (mounted) {
              setState(() {
                _paymentConfirmedBySocket = true;
                _waitingForPaymentConfirmation = false;
              });
            }
            AppNotification.showSuccess(context, 'Payment verified!');
            await Future.delayed(const Duration(milliseconds: 200));
            // Now mark the booking as complete after payment is verified
            if (mounted) {
              final token = await TokenStorage.getToken();
              if (token != null && token.isNotEmpty) {
                await _completeBookingAndShowRating(token);
              } else {
                if (mounted) await _showRatingBottomSheet();
              }
            }
            return;
          }
        }

        if (_paymentConfirmedBySocket) {
          AppNotification.showSuccess(context, 'Payment confirmed');
          await Future.delayed(const Duration(milliseconds: 200));
          // Mark the booking as complete after socket confirmation
          if (mounted) {
            final token = await TokenStorage.getToken();
            if (token != null && token.isNotEmpty) {
              await _completeBookingAndShowRating(token);
            } else {
              if (mounted) await _showRatingBottomSheet();
            }
          }
          return;
        }

        AppNotification.showSuccess(context, 'Payment processing...');
        await _waitForPaymentConfirmation();
      } else {
        AppNotification.showError(context, 'Payment was cancelled or failed');
        if (mounted) {
          setState(() {
            _waitingForPaymentConfirmation = false;
          });
        }
      }
    } catch (e) {
      _paymentWebViewOpen = false;
      if (_kDebugMode) debugPrint('Error handling payment WebView: $e');
      AppNotification.showError(context, 'Error processing payment: $e');
      if (mounted) {
        setState(() {
          _waitingForPaymentConfirmation = false;
        });
      }
    }
  }

  /// Wait for payment confirmation from backend via socket
  /// Shows a loading indicator while waiting (max 60 seconds)
  /// Falls back to API verification if socket doesn't respond
  Future<void> _waitForPaymentConfirmation() async {
    try {
      if (!mounted) return;

      if (_paymentConfirmedBySocket) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted && !_submittingReview) {
          // Mark booking as complete after socket confirmed payment
          final token = await TokenStorage.getToken();
          if (token != null && token.isNotEmpty) {
            await _completeBookingAndShowRating(token);
          } else {
            await _showRatingBottomSheet();
          }
        }
        return;
      }

      setState(() {
        _waitingForPaymentConfirmation = true;
      });

      if (_kDebugMode) {
        debugPrint(
            'MessageClient: Waiting for payment confirmation from socket...');
      }

      // Show loading dialog while waiting
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      FlutterFlowTheme.of(context).primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Verifying payment...',
                    style: FlutterFlowTheme.of(context).bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      _paymentConfirmationDialogOpen = true;

      // Set up timeout for socket confirmation (60 seconds max)
      _paymentConfirmationTimeout = Timer(const Duration(seconds: 60), () {
        if (!_paymentConfirmedBySocket && mounted) {
          if (_kDebugMode) {
            debugPrint(
                'MessageClient: Payment confirmation timeout - falling back to API verification');
          }
          _verifyPaymentViaAPI();
        }
      });

      // Wait for either:
      // 1. Socket confirmation via _handlePaymentConfirmed()
      // 2. Timeout after 60 seconds (triggers API verification)
      // _paymentConfirmedBySocket will be set to true when socket event arrives
    } catch (e) {
      if (_kDebugMode) debugPrint('Error waiting for payment confirmation: $e');
      if (mounted) {
        _closePaymentConfirmationDialogIfOpen();
        AppNotification.showError(context, 'Error verifying payment: $e');
      }
    }
  }

  /// Verify payment status via API call
  /// Called if socket confirmation doesn't arrive within 60 seconds
  Future<void> _verifyPaymentViaAPI() async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) _closePaymentConfirmationDialogIfOpen();
        AppNotification.showError(context, 'Session expired');
        return;
      }

      final headers = <String, String>{'Authorization': 'Bearer $token'};

      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final parsed = jsonDecode(response.body);
          final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
          final booking = data is Map ? data['booking'] ?? data : null;

          final paymentStatus =
              booking is Map ? booking['paymentStatus']?.toString() : null;

          if (_kDebugMode) {
            debugPrint(
                'MessageClient: API verification - payment status: $paymentStatus');
          }

          if (paymentStatus == 'paid') {
            // Payment is confirmed via API
            if (mounted) {
              _closePaymentConfirmationDialogIfOpen();
              setState(() {
                _paymentConfirmedBySocket = true;
                _waitingForPaymentConfirmation = false;
              });
              AppNotification.showSuccess(context, 'Payment verified!');
              await Future.delayed(const Duration(milliseconds: 200));
              // Mark the booking as complete after payment is verified via API
              await _completeBookingAndShowRating(token);
            }
            return;
          }
        } catch (e) {
          if (_kDebugMode) debugPrint('Error parsing booking data: $e');
        }
      }

      // If we get here, payment status is still unclear
      if (mounted) {
        _closePaymentConfirmationDialogIfOpen();
        AppNotification.showError(
          context,
          'Payment verification pending. Please check your account or try again in a moment.',
        );
        setState(() => _waitingForPaymentConfirmation = false);
      }
    } catch (e) {
      if (_kDebugMode) debugPrint('Error verifying payment via API: $e');
      if (mounted) {
        _closePaymentConfirmationDialogIfOpen();
        AppNotification.showError(context, 'Error verifying payment: $e');
        setState(() => _waitingForPaymentConfirmation = false);
      }
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
                color: isDark ? const Color(0xFF1F2937) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24.0)),
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
                  bottom: MediaQuery.of(ctx).viewInsets.bottom +
                      (isSmallScreen ? 16 : 20),
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
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
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
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF111827),
                                              )
                                            : theme.titleLarge.override(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF111827),
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
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
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
                                      ? const Color(
                                          0xFF10B981) // Green for good ratings
                                      : selectedRating >= 3
                                          ? const Color(
                                              0xFFF59E0B) // Amber for average ratings
                                          : const Color(
                                              0xFFEF4444), // Red for poor ratings
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    onPressed: () =>
                                        setState(() => selectedRating = idx),
                                    iconSize: isSmallScreen ? 32 : 38,
                                    icon: Icon(
                                      idx <= selectedRating
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
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
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
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
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF111827),
                                fontSize: isSmallScreen ? 14 : 15,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Share your experience with this artisan...',
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
                      if (_reviewAlreadySubmitted &&
                          _reviewConflictMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF4B2113)
                                : const Color(0xFFFEEAE6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isDark
                                    ? const Color(0xFF7F1D1D)
                                    : const Color(0xFFF5C2BD)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: isDark
                                      ? const Color(0xFFFFD2CE)
                                      : const Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_reviewConflictMessage!,
                                      style: theme.bodyMedium.copyWith(
                                          color: isDark
                                              ? const Color(0xFFFFD2CE)
                                              : const Color(0xFF92400E)))),
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
                                      final ok = await _submitReview(
                                          selectedRating,
                                          _reviewCtrl.text.trim());
                                      setState(() => submitting = false);
                                      if (ok &&
                                          Navigator.of(sheetContext).canPop()) {
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
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
      if (widget.bookingId != null && widget.bookingId!.isNotEmpty)
        body['bookingId'] = widget.bookingId;

      final uri = Uri.parse('$API_BASE_URL/api/reviews');
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppNotification.showSuccess(context, 'Review submitted. Thank you!');
        // Clear any previous conflict state
        setState(() {
          _reviewAlreadySubmitted = false;
          _reviewConflictMessage = null;
        });
        return true;
      } else if (response.statusCode == 409) {
        // Conflict — user already submitted a review for this target
        String serverMsg = 'You have already reviewed this artisan.';
        try {
          final parsed =
              response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
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
          final parsed =
              response.body.isNotEmpty ? jsonDecode(response.body) : null;
          if (parsed is Map &&
              (parsed['message'] != null || parsed['error'] != null)) {
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
    if (_bookingCompleted)
      return const Text('Completed', style: TextStyle(fontSize: 13));
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
