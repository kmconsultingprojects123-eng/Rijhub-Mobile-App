import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/token_storage.dart';
import '../../api_config.dart';
import '../payment_webview/payment_webview_page_widget.dart';
import '../../services/user_service.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/auth_guard.dart';
import '../../services/webview_monitor.dart';
import '../booking_page/booking_page_widget.dart';
import '../../utils/app_notification.dart';
import '../login_account/login_account_widget.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '/index.dart';
import '../../services/flow_guard.dart';
import '../../services/notification_service.dart';
import '../../state/app_state_notifier.dart' as app_state_notifier;
import '/main.dart';

// Lightweight, safe payment init widget. This file is intentionally
// simplified compared to the original to remove parser-sensitivity
// and ensure in-app webview is reachable via a dialog fallback.

// Helper: normalize base URL for API calls
String _normalizeBaseUrl(String raw) {
  var base = raw.trim();
  if (base.isEmpty) return '';
  if (!base.startsWith(RegExp(r'https?://'))) base = 'https://$base';
  base = base.replaceAll(RegExp(r'/+$'), '');
  return base;
}

class PaymentInitPageWidget extends StatefulWidget {
  final Map<String, dynamic> payment;
  final Map<String, dynamic>? booking;
  final Map<String, dynamic>? quote;

  const PaymentInitPageWidget({super.key, required this.payment, this.booking, this.quote});

  @override
  State<PaymentInitPageWidget> createState() => _PaymentInitPageWidgetState();
}

enum _PaymentState { checkout, initializing, inApp, verifying, success }

class _PaymentInitPageWidgetState extends State<PaymentInitPageWidget> {
  _PaymentState _state = _PaymentState.checkout;
  bool _blocking = false;
  bool _loading = false;
  String? _lastVerifyResponse;
  String? _authUrl;
  String? _reference;
  dynamic _amount;
  String? _email;
  String? _bookingId;
  String? _quoteId;
  // Keep the original payment initialization payload so we can reuse fields
  // (like artisanId) later when creating the booking after payment verification.
  Map<String, dynamic>? _initRequestPayload;

  @override
  void initState() {
    super.initState();
    _resolveInitialData();
    _populateEmail();
  }

  // Use a slightly longer timeout for payment-related network calls; webhooks and gateway
  // verifications can sometimes be slow, so 30s avoids premature failures.
  static const Duration _paymentRequestTimeout = Duration(seconds: 30);

  void _resolveInitialData() {
    final payment = Map<String, dynamic>.from(widget.payment);
    // try to read common keys
    _authUrl = _findKey(payment, ['authorization_url', 'authorizationUrl', 'authorization', 'auth_url', 'url', 'authUrl', 'access_url'])?.toString();
    _reference = _findKey(payment, ['reference', 'ref', 'tx_ref', 'transaction_reference'])?.toString();
    // If reference not found, try to extract it from the authUrl query parameters (common in Paystack)
    if ((_reference == null || _reference!.isEmpty) && _authUrl != null && _authUrl!.isNotEmpty) {
      try {
        final u = Uri.tryParse(_authUrl!);
        if (u != null) {
          final q = u.queryParameters;
          final refKeys = ['reference', 'ref', 'tx_ref', 'trxref', 'transaction_reference', 'transaction', 'payment_reference'];
          for (final k in refKeys) {
            if (q.containsKey(k) && q[k] != null && q[k]!.isNotEmpty) {
              _reference = q[k];
              break;
            }
          }
        }
      } catch (_) {}
    }
    // amount heuristics - prefer explicit values provided in quote if available
    dynamic amount;
    try {
      if (widget.quote != null) {
        final q = widget.quote as Map<String, dynamic>;
        // common direct keys to check first
        for (final k in ['amount', 'price', 'total', 'quoteTotal', 'proposedPrice', 'perJob', 'per_hour', 'hourlyRate']) {
          if (q.containsKey(k) && q[k] != null) {
            amount = q[k];
            break;
          }
        }
        // if still null, try deep find in quote
        amount ??= _findKey(q, ['total', 'amount', 'price', 'quoteTotal', 'proposedPrice']);
      }
    } catch (_) {
      amount = null;
    }
    // fallback to payment node if quote didn't provide amount
    amount ??= _findKey(payment, ['total', 'amount', 'price', 'quoteTotal', 'proposedPrice']) ?? payment['amount'] ?? payment['authorization']?['amount'];
    if (amount is String) {
      final parsed = num.tryParse(amount.replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (parsed != null) amount = parsed;
    }
    // If provider-style amount (like paystack in kobo), normalize when obviously large
    try {
      if (amount is num && amount >= 100000 && !(payment['currency'] != null)) {
        // probably kobo -> divide by 100
        amount = amount / 100;
      }
    } catch (_) {}
    _amount = amount;
    _bookingId = widget.booking?['_id']?.toString() ?? widget.booking?['id']?.toString();
    // Do not disable the Pay button on initial load. The button should only be
    // disabled while verifying payment or while creating a booking. We keep
    // `_blocking` controlled where those operations occur so the user can tap
    // Pay if no flow is in progress.
    if (kDebugMode) debugPrint('PaymentInit(init): amount=$_amount authUrl=$_authUrl ref=$_reference bookingId=${_bookingId ?? '<null>'} blocking=${_blocking}');
  }

  dynamic _findKey(dynamic node, List<String> keys) {
    if (node == null) return null;
    if (node is Map) {
      for (final k in keys) {
        if (node.containsKey(k) && node[k] != null) return node[k];
      }
      for (final v in node.values) {
        final res = _findKey(v, keys);
        if (res != null) return res;
      }
    } else if (node is List) {
      for (final e in node) {
        final res = _findKey(e, keys);
        if (res != null) return res;
      }
    }
    return null;
  }

  // Helper: try several standard locations to extract the artisan's user id
  String? _resolveArtisanUserId() {
    try {
      // 1. Booking object (cast to non-null Map to satisfy null-safety)
      final b = widget.booking;
      if (b is Map) {
        final mb = Map<String, dynamic>.from(b as Map<dynamic, dynamic>);
        final candidates = [
          mb['artisanId'],
          mb['artisan_user'] ?? mb['artisanUser'] ?? mb['artisan'],
          mb['userId'],
          mb['user'] is Map ? (mb['user']['_id'] ?? mb['user']['id']) : null,
        ];
        for (final c in candidates) {
          if (c == null) continue;
          if (c is Map) {
            final id = c['_id'] ?? c['id'];
            if (id != null) return id.toString();
          }
          final s = c.toString();
          if (s.isNotEmpty) return s;
        }
      }

      // 2. Quote object
      final q = widget.quote;
      if (q is Map) {
        final mq = Map<String, dynamic>.from(q as Map<dynamic, dynamic>);
        final candidates = [mq['artisanId'], mq['userId'], mq['ownerId'], mq['artisan_user'] ?? mq['artisanUser'] ?? mq['artisan']];
        for (final c in candidates) {
          if (c == null) continue;
          if (c is Map) {
            final id = c['_id'] ?? c['id'];
            if (id != null) return id.toString();
          }
          final s = c.toString();
          if (s.isNotEmpty) return s;
        }
      }

      // 3. Payment payload & metadata
      final p = widget.payment;
      if (p is Map) {
        final meta = p['metadata'];
        if (meta is Map) {
          for (final k in ['artisanId', 'artisan', 'artisan_id', 'userId', 'user_id']) {
            final v = meta[k];
            if (v != null && v.toString().isNotEmpty) return v.toString();
          }
        }
        for (final k in ['artisanId', 'artisan', 'userId']) {
          final v = p[k];
          if (v != null) {
            if (v is Map) {
              final id = v['_id'] ?? v['id'];
              if (id != null) return id.toString();
            }
            final s = v.toString();
            if (s.isNotEmpty) return s;
          }
        }
      }

      // 4. Init request payload snapshot
      if (_initRequestPayload != null) {
        final cand = _initRequestPayload!['artisanId'] ?? (_initRequestPayload!['metadata'] is Map ? _initRequestPayload!['metadata']['artisanId'] : null);
        if (cand != null && cand.toString().isNotEmpty) return cand.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _populateEmail() async {
    try {
      final profile = await UserService.getProfile();
      setState(() => _email = profile?['email']?.toString() ?? '');
    } catch (_) {
      setState(() => _email = '');
    }
  }

  String _displayAmount(dynamic a) {
    try {
      if (a == null) return '-';
      if (a is num) return '₦' + NumberFormat('#,##0', 'en_US').format(a);
      final numVal = num.tryParse(a.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (numVal != null) return '₦' + NumberFormat('#,##0', 'en_US').format(numVal);
      return a.toString();
    } catch (_) {
      return a.toString();
    }
  }

  Future<void> _initPaymentThenStart() async {
    if (_blocking) return;
    if (needsSignInForAction()) {
      await showGuestAuthRequiredDialog(context, message: 'You need to sign in or create an account to make payments.');
      return;
    }
    setState(() {
      _state = _PaymentState.initializing;
      _loading = true;
      _blocking = true;
    });

    // Ensure email present
    if ((_email == null || _email!.trim().isEmpty)) {
      await _populateEmail();
    }

    // If this is a quote-based payment, try to accept the quote first so the booking is marked accepted
    if (_isQuotePayment()) {
      bool accepted = false;
      try {
        accepted = await _acceptQuoteIfNeeded();
      } catch (e) {
        if (kDebugMode) debugPrint('Quote accept attempt threw: $e');
        accepted = false;
      }

      if (!accepted) {
        // If acceptance failed due to missing auth, offer the user to sign in and retry.
        final choice = await showDialog<String?>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Accept quote required'),
            content: const Text('We could not accept the quote automatically. You may need to sign in or try again. Would you like to sign in now?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop('cancel'), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop('signin'), child: const Text('Sign in')),
            ],
          ),
        );

        if (choice == 'signin') {
          try {
            await NavigationUtils.safePushNoAuth(context, LoginAccountWidget());
          } catch (_) {
            try {
              await NavigationUtils.safePush(context, LoginAccountWidget());
            } catch (_) {}
          }

          // After sign in, try accepting quote again once
          bool accepted2 = false;
          try {
            accepted2 = await _acceptQuoteIfNeeded();
          } catch (_) { accepted2 = false; }

          if (!accepted2) {
            AppNotification.showError(context, 'Could not accept quote after sign in. Payment aborted.');
            setState(() { _state = _PaymentState.checkout; _loading = false; _blocking = false; });
            return;
          }
        } else {
          // User cancelled — abort flow
          AppNotification.showInfo(context, 'Payment aborted — quote acceptance required');
          setState(() { _state = _PaymentState.checkout; _loading = false; _blocking = false; });
          return;
        }
      }

      // If the server accepted the quote and returned a payment initialization (authorization_url/reference),
      // we should start the in-app payment immediately using that URL instead of calling /api/payments/initialize.
      if (_authUrl != null && _authUrl!.isNotEmpty) {
        // start in-app using server-provided auth url
        try {
          await _startInAppPayment();
        } finally {
          // ensure UI state is reset appropriately by _startInAppPayment path
        }
        return;
      }
    }

    // Build init payload
    final bodyMap = <String, dynamic>{
      'amount': _amount,
      'currency': 'NGN',
      'email': _email,
    };
    // Save a snapshot of the final init payload (including any artisanId/bookingSource additions)
    try { _initRequestPayload = Map<String, dynamic>.from(bodyMap); } catch (_) { _initRequestPayload = null; }

    try {
      // Try to include artisanId proactively so the initialize endpoint knows which artisan this is for
      final aid = _resolveArtisanUserId();
      if (aid != null && aid.isNotEmpty) {
        bodyMap['artisanId'] = aid;
      }
    } catch (_) {}
    try {
      final qid = widget.quote?['_id'] ?? widget.quote?['id'] ?? widget.quote?['quoteId'];
      if (qid != null) {
        bodyMap['quoteId'] = qid;
        _quoteId = qid?.toString();
      }
      // If this init is coming from a quote, mark bookingSource explicitly so server can auto-accept bookings
      try {
        if (qid != null && qid.toString().isNotEmpty) {
          final meta = bodyMap['metadata'] is Map ? Map<String, dynamic>.from(bodyMap['metadata']) : <String, dynamic>{};
          meta['bookingSource'] = meta['bookingSource'] ?? 'quote';
          bodyMap['metadata'] = meta;
          bodyMap['bookingSource'] = bodyMap['bookingSource'] ?? 'quote';
        }
      } catch (_) {}
    } catch (_) {}

    try {
      // Attach authorization when available so protected endpoints work (fixes 401 Missing Bearer token)
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      // If we have a bookingId (created/returned by quote accept), prefer booking-scoped pay-with-quote init.
      http.Response resp;
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/bookings/${_bookingId!}/pay-with-quote');
        if (kDebugMode) debugPrint('Initializing payment via booking-scoped endpoint -> $uri');
        resp = await http.post(uri, headers: headers, body: jsonEncode(bodyMap)).timeout(const Duration(seconds: 10));
      } else {
        final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/payments/initialize');
        if (kDebugMode) debugPrint('Initializing payment via generic endpoint -> $uri');
        resp = await http.post(uri, headers: headers, body: jsonEncode(bodyMap)).timeout(const Duration(seconds: 10));
      }
      if (kDebugMode) debugPrint('Payment init response -> ${resp.statusCode} ${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        _authUrl = data['authorization_url']?.toString() ?? _authUrl;
        _reference = data['reference']?.toString() ?? _reference;
        // Also merge server-returned payment node back into our saved init payload
        try {
          if (_initRequestPayload == null) _initRequestPayload = <String, dynamic>{};
          if (data is Map) {
            // preserve any fields server returned that may be useful
            _initRequestPayload!.addAll({'serverPayment': data});
          }
        } catch (_) {}
      } else {
        String serverMsg = '';
        try {
          final ebody = jsonDecode(resp.body);
          if (ebody is Map) serverMsg = ebody['message']?.toString() ?? ebody['error']?.toString() ?? '';
        } catch (_) {}
        // Friendly error for unauthorized. Offer to take the user to sign-in flow.
        if (resp.statusCode == 401) {
          // Let user know their session is invalid and offer sign-in.
          final choice = await showDialog<String?>(
            context: context,
            barrierDismissible: true,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign in required'),
              content: const Text('You need to be signed in to make payments. Would you like to sign in now?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop('cancel'), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop('signin'), child: const Text('Sign in')),
              ],
            ),
          );
          if (choice == 'signin') {
            try {
              await NavigationUtils.safePushNoAuth(context, LoginAccountWidget());
            } catch (_) {
              try { await NavigationUtils.safePush(context, LoginAccountWidget()); } catch (_) {}
            }
            // navigation to login performed; abort current flow so user can retry after logging in
            return;
          }
          AppNotification.showError(context, 'Session required — sign in to continue');
        } else {
          AppNotification.showError(context, serverMsg.isNotEmpty ? serverMsg : 'Payment initialization failed.');
        }
        setState(() {
          _state = _PaymentState.checkout;
          _loading = false;
          _blocking = false;
        });
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Payment init error: $e');
      AppNotification.showError(context, 'Payment initialization failed. Please try again.');
      setState(() {
        _state = _PaymentState.checkout;
        _loading = false;
        _blocking = false;
      });
      return;
    }

    // start in-app
    if (_authUrl != null && _authUrl!.isNotEmpty) {
      await _startInAppPayment();
    } else {
      AppNotification.showError(context, 'Payment link not available');
      setState(() {
        _state = _PaymentState.checkout;
        _loading = false;
        _blocking = false;
      });
    }
  }

  Future<dynamic> _startInAppPayment() async {
    if (_authUrl == null || _authUrl!.isEmpty) return null;
    // Mark payment flow active so global replace-all redirects defer.
    try { FlowGuard.setPaymentActive(true); } catch (_) {}
    setState(() {
      _state = _PaymentState.inApp;
      _loading = false;
    });

    try {
      // mark monitor (best-effort)
      try { WebviewMonitor.start(); } catch (_) {}
      final page = PaymentWebviewPageWidget(url: _authUrl!, successUrlContains: _reference);
      final result = await _openWebviewDialog(page);
      if (kDebugMode) debugPrint('Webview dialog returned: $result');
      // interpret result
      bool success = false;
      String? returnedUrl;
      if (result == true) success = true;
      else if (result is Map) {
        success = result['success'] == true;
        returnedUrl = result['url']?.toString();
      }

      if (!success) {
        // Clear payment guard before returning.
        try { FlowGuard.setPaymentActive(false); } catch (_) {}

        // Reset UI state and show a friendly bottom sheet that allows retry or go home.
        if (mounted) {
          setState(() {
            _state = _PaymentState.checkout;
            _blocking = false;
            _loading = false;
          });

          final jobTitle = widget.booking?['service'] ?? widget.quote?['title'] ?? widget.payment['service']?.toString();
          final bookingPrice = (_amount ?? widget.booking?['price'] ?? widget.quote?['amount'] ?? widget.payment['amount'])?.toString();
          final bookingDateTime = widget.booking?['schedule'] ?? widget.quote?['schedule'] ?? widget.payment['schedule']?.toString();

          try {
            await _showBookingFailedBottomSheet(jobTitle?.toString(), bookingPrice?.toString(), bookingDateTime?.toString());
          } catch (e) {
            if (kDebugMode) debugPrint('Error showing booking failed bottom sheet: $e');
            AppNotification.showInfo(context, 'Payment cancelled — you can retry');
          }
        } else {
          // Fallback: notify user
          try { AppNotification.showInfo(context, 'Payment cancelled — you can retry'); } catch (_) {}
        }
        return result;
      }

      // try to extract reference from returnedUrl when possible (do this before verification)
      if (returnedUrl != null && returnedUrl.isNotEmpty) {
        try {
          final uri = Uri.tryParse(returnedUrl);
          if (uri != null) {
            final q = uri.queryParameters;
            if ((_reference == null || _reference!.isEmpty) && (q['reference'] ?? q['ref'] ?? q['tx_ref']) != null) {
              _reference = (q['reference'] ?? q['ref'] ?? q['tx_ref'])?.toString();
            }
          }
        } catch (_) {}
      }

      // Before creating a booking, verify the payment so we only show the "Booking created" sheet
      // when the payment has actually been confirmed.
      bool verified = false;
      if (mounted) {
        // show a modal verifying dialog
        // Mark UI as blocking so the Pay button is disabled while verifying
        setState(() { _state = _PaymentState.verifying; _blocking = true; _loading = true; });
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => WillPopScope(
            onWillPop: () async => false,
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 40),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(children: const [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Verifying payment...'))]),
              ),
            ),
          ),
        );
      }

      try {
        // Run verification once (the function performs robust checks and may try alternate refs)
        verified = await _verifyPayment();
        if (kDebugMode) debugPrint('Immediate verification result -> $verified');
      } catch (e) {
        if (kDebugMode) debugPrint('Verification attempt error: $e');
        verified = false;
      } finally {
        try { if (mounted) Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
      }

      if (!verified) {
        // Payment didn't verify immediately — treat as failure here and show failed bottom sheet.
        try { FlowGuard.setPaymentActive(false); } catch (_) {}
        if (mounted) {
          setState(() { _state = _PaymentState.checkout; _blocking = false; _loading = false; });
          final jobTitle = widget.booking?['service'] ?? widget.quote?['title'] ?? widget.payment['service']?.toString();
          final bookingPrice = (_amount ?? widget.booking?['price'] ?? widget.quote?['amount'] ?? widget.payment['amount'])?.toString();
          final bookingDateTime = widget.booking?['schedule'] ?? widget.quote?['schedule'] ?? widget.payment['schedule']?.toString();
          try {
            await _showBookingFailedBottomSheet(jobTitle?.toString(), bookingPrice?.toString(), bookingDateTime?.toString());
          } catch (e) {
            if (kDebugMode) debugPrint('Error showing booking failed bottom sheet after verification failure: $e');
            AppNotification.showInfo(context, 'Payment not verified — you can retry');
          }
        } else {
          try { AppNotification.showInfo(context, 'Payment not verified — you can retry'); } catch (_) {}
        }
        return result;
      }

      // Verified == true. Proceed to create booking (mark as pending for artisan acceptance), then try to confirm booking payment.
      String? threadIdFromCreation;
      Map<String, String?>? created;

      // If caller provided a booking object (e.g., from earlier server create in ArtisanDetail), prefer its threadId
      try {
        final suppliedTid = widget.booking?['threadId']?.toString() ?? widget.booking?['chat']?['_id']?.toString() ?? widget.booking?['_id']?.toString();
        if (suppliedTid != null && suppliedTid.isNotEmpty) {
          threadIdFromCreation = suppliedTid;
          if (kDebugMode) debugPrint('PaymentInit: using supplied booking.threadId=${threadIdFromCreation}');
        }
        // Also prefer supplied bookingId if present
        if ((_bookingId == null || _bookingId!.isEmpty) && widget.booking?['_id'] != null) {
          _bookingId = widget.booking?['_id']?.toString();
          if (kDebugMode) debugPrint('PaymentInit: using supplied booking._id=${_bookingId}');
        }
      } catch (_) {}

      if (_bookingId == null || _bookingId!.isEmpty) {
        if (mounted) {
          // While creating booking, mark UI as blocking so Pay button stays disabled
          setState(() { _state = _PaymentState.verifying; _blocking = true; _loading = true; });
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => WillPopScope(
              onWillPop: () async => false,
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 40),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(children: const [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Creating booking...'))]),
                ),
              ),
            ),
          );
        }

        try {
          // If this was a quote-based payment, the server webhook may create the booking
          // (Paystack webhook will create booking and mark it paid). Prefer polling the
          // quote endpoint to detect the server-created booking instead of creating it client-side.
          if (_isQuotePayment()) {
            String? qid;
            try { qid = widget.quote?['_id']?.toString() ?? widget.payment['quoteId']?.toString() ?? widget.payment['quote']?['_id']?.toString(); } catch (_) { qid = null; }
            // Use stored _quoteId if available
            qid ??= _quoteId;
            final polled = await _pollForBookingFromQuote(qid, maxAttempts: 6, initialDelay: const Duration(seconds: 1));
            if (polled != null) {
              _bookingId = polled['bookingId'];
              threadIdFromCreation = polled['threadId'];
              if (kDebugMode) debugPrint('Polled booking from quote -> bookingId=$_bookingId threadId=$threadIdFromCreation');
            } else {
              if (kDebugMode) debugPrint('Polling for server-created booking returned null for quoteId=$qid');
              // If polling failed, show awaiting confirmation sheet and return
              if (mounted && qid != null && qid.isNotEmpty) {
                await _showAwaitingServerConfirmationBottomSheet(qid);
                try { if (mounted) Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
                return;
              }
            }
          } else {
            created = await _createBookingAfterPayment();
            if (created != null) {
              _bookingId = created['bookingId'];
              threadIdFromCreation = created['threadId'];
              if (kDebugMode) debugPrint('Booking created in _startInAppPayment after verification: bookingId=$_bookingId threadId=$threadIdFromCreation');
            } else {
              if (kDebugMode) debugPrint('Booking creation returned null even after verification');
            }
          }
        } finally {
          try { if (mounted) Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
        }
      }

      // If booking was just created for a quote payment, try accepting the quote now
      // (server may only expose booking-scoped accept endpoints that become available
      // after booking creation). If acceptance succeeds, poll for the updated booking
      // state so the UI observes the accepted/paid state promptly.
      if (_isQuotePayment() && _bookingId != null && _bookingId!.isNotEmpty) {
        try {
          final acceptedAfterPayment = await _acceptQuoteIfNeeded();
          if (kDebugMode) debugPrint('Accept-after-payment attempt -> $acceptedAfterPayment for bookingId=$_bookingId');
          if (acceptedAfterPayment) {
            try {
              final latestBooking = await _pollBookingStatus(_bookingId!, maxAttempts: 6, initialDelay: const Duration(seconds: 2));
              if (latestBooking != null) {
                final serverTid = (latestBooking['threadId'] ?? latestBooking['chat']?['_id'])?.toString();
                if (serverTid != null && serverTid.isNotEmpty) threadIdFromCreation = serverTid;
              }
            } catch (e) {
              if (kDebugMode) debugPrint('Polling after accept failed: $e');
            }
          }
        } catch (e) { if (kDebugMode) debugPrint('Accept-after-payment error: $e'); }
      }

      // If booking was created, attempt to confirm the booking payment on backend immediately.
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        try {
          // For quote payments we don't need to call confirm-payment: the booking
          // should already be created with status 'accepted'. Confirm endpoint is
          // mainly for direct-hire flows where payment needs to be attached.
          if (_isQuotePayment()) {
            // IMPORTANT: confirming a booking payment (POST /api/bookings/:id/confirm-payment)
            // must be done by a trusted server process (webhook handler). Do NOT call
            // the protected confirm endpoint from the client. Instead we wait for the
            // server webhook to process the payment and update booking.paymentStatus.
            if (kDebugMode) debugPrint('Quote flow: not calling protected confirm endpoint from client; polling for server webhook to mark payment as paid for bookingId=$_bookingId');

            // Best-effort: poll the booking status so UI can observe accepted state once
            // the server webhook has run and updated the booking record.
            try {
              final latestBooking = await _pollBookingStatus(_bookingId!, maxAttempts: 6, initialDelay: const Duration(seconds: 2));
              if (mounted) {
                AppNotification.showSuccess(context, 'Payment verified and booking created.');
                try {
                  final cnt = await NotificationService.fetchUnreadCount();
                  try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
                } catch (_) {}
              }
              if (latestBooking != null) {
                final serverTid = (latestBooking['threadId'] ?? latestBooking['chat']?['_id'])?.toString();
                if (serverTid != null && serverTid.isNotEmpty) threadIdFromCreation = serverTid;
              }
            } catch (e) {
              if (kDebugMode) debugPrint('Quote booking poll error: $e');
            }
          } else {
            try {
              await _confirmBookingPayment(_bookingId!);
              // After confirming the booking payment, poll the booking endpoint briefly so the client
              // can observe the server-driven transition to 'awaiting-acceptance' (webhook/confirm may be async).
              Map<String, dynamic>? latestBooking;
              try {
                latestBooking = await _pollBookingStatus(_bookingId!, maxAttempts: 6, initialDelay: const Duration(seconds: 2));
              } catch (_) { latestBooking = null; }

              if (mounted) {
                AppNotification.showSuccess(context, 'Payment verified and payment is held in escrow. Booking created.');
                // Refresh unread notification count so the UI shows new server-side notifications (artisan/customer)
                try {
                  final cnt = await NotificationService.fetchUnreadCount();
                  try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
                } catch (_) {}
              }

              // If polling found the booking and it reached awaiting/accepted state, update local bookingId/threadId as needed
              try {
                if (latestBooking != null) {
                  final serverTid = (latestBooking['threadId'] ?? latestBooking['chat']?['_id'])?.toString();
                  if (serverTid != null && serverTid.isNotEmpty) {
                    threadIdFromCreation = serverTid;
                  }
                }
              } catch (_) {}
            } catch (e) {
              // Treat confirm failures specially: if it's a 404/no-pending and this is a quote flow,
              // consider it non-fatal. For direct-hire flows, show info and continue.
              if (kDebugMode) debugPrint('Immediate confirm booking payment failed: $e');
              if (mounted) AppNotification.showInfo(context, _isQuotePayment() ? 'Payment verified and booking created.' : 'Payment verified awaiting artisan response.');
              // Even if confirm failed, refresh counts (server/webhook may have created notifications)
              try {
                final cnt = await NotificationService.fetchUnreadCount();
                try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
              } catch (_) {}
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error confirming booking payment: $e');
        }
      }

      // If booking created but no threadId returned, attempt to fetch the chat thread immediately
      if ((_bookingId != null && _bookingId!.isNotEmpty) && (threadIdFromCreation == null || threadIdFromCreation!.isEmpty)) {
        try {
          final fetchedTid = await _fetchThreadIdForBooking(_bookingId!);
          if (kDebugMode) debugPrint('fetchThreadIdForBooking -> bookingId=${_bookingId} fetchedThreadId=${fetchedTid ?? '<null>'}');
          if (fetchedTid != null && fetchedTid.isNotEmpty) threadIdFromCreation = fetchedTid;
        } catch (e) {
          if (kDebugMode) debugPrint('Error fetching thread for booking: $e');
        }
      }

      // Show bottom-sheet UI to let the user view booking history now that payment is verified and booking exists (or failed to create).
      try {
        final jobTitle = widget.booking?['service'] ?? widget.quote?['title'] ?? widget.payment['service']?.toString() ?? '';
        final bookingPrice = (_amount ?? widget.booking?['price'] ?? widget.quote?['amount'] ?? widget.payment['amount'])?.toString();
        final bookingDateTime = widget.booking?['schedule'] ?? widget.quote?['schedule'] ?? widget.payment['schedule'] ?? DateTime.now().toUtc().toIso8601String();
        // Clear blocking state so the bottom sheet is interactive
        if (mounted) {
          if (_bookingId != null && _bookingId!.isNotEmpty) {
            // booking created successfully -> keep blocked
            setState(() { _blocking = true; _loading = false; _state = _PaymentState.success; });
          } else {
            // booking not created -> allow retry
            setState(() { _blocking = false; _loading = false; _state = _PaymentState.success; });
          }
        }
        if (_bookingId != null && _bookingId!.isNotEmpty) {
          await _showBookingCreatedBottomSheet(_bookingId!, threadIdFromCreation, jobTitle?.toString(), bookingPrice?.toString(), bookingDateTime?.toString());
        } else {
          await _showBookingFailedBottomSheet(jobTitle?.toString(), bookingPrice?.toString(), bookingDateTime?.toString());
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error showing booking bottom sheet after verification/create: $e');
      }

      // Start background verification as a safety net (idempotent) so the app keeps retrying if needed.
      try { _startBackgroundVerification(_bookingId != null && _bookingId!.isNotEmpty ? _bookingId! : null); } catch (_) {}
      // Clear the payment guard now that navigation is performed/attempted.
      try { FlowGuard.setPaymentActive(false); } catch (_) {}
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Error in _startInAppPayment: $e');
      AppNotification.showError(context, 'Could not open in-app payment. Opening browser as fallback.');
      try { final uri = Uri.tryParse(_authUrl!); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
      setState(() { _state = _PaymentState.checkout; _loading = false; _blocking = false; });
      // Clear payment guard in error path
      try { FlowGuard.setPaymentActive(false); } catch (_) {}
      return null;
    }
  }

  // Run payment verification in background; when verified, call booking confirm endpoint.
  Future<void> _startBackgroundVerification(String? bookingId) async {
    // Run in isolate-like background flow (fire-and-forget). We intentionally do not set
    // UI state to 'verifying' so the user experience is not blocked.
    const maxAttempts = 6;
    var verified = false;
    for (var attempt = 1; attempt <= maxAttempts && !verified; attempt++) {
      if (kDebugMode) debugPrint('Background verify attempt $attempt/$maxAttempts');
      try {
        verified = await _verifyPayment();
      } catch (e) {
        if (kDebugMode) debugPrint('Background verify error: $e');
        verified = false;
      }
      if (!verified && attempt < maxAttempts) {
        final waitMs = 2000 * (1 << (attempt - 1)); // 2s,4s,8s,16s...
        if (kDebugMode) debugPrint('Background verification failed, retrying in ${waitMs}ms');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }

    if (verified) {
      if (kDebugMode) debugPrint('Background verification succeeded');
      // Inform backend to confirm booking payment if we have a booking
      if (bookingId != null && bookingId.isNotEmpty) {
        // For quote flows we consider booking created & accepted immediately; no confirm call required.
        if (_isQuotePayment()) {
          if (kDebugMode) debugPrint('Background verification: quote flow detected, skipping confirm for bookingId=$bookingId');
          if (mounted) {
            AppNotification.showSuccess(context, 'Payment verified and booking created (quote).');
            try {
              final cnt = await NotificationService.fetchUnreadCount();
              try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
            } catch (_) {}
          }
        } else {
          try {
            await _confirmBookingPayment(bookingId);
            // notify user unobtrusively
            if (mounted) {
              AppNotification.showSuccess(context, 'Payment verified for your booking');
              try {
                final cnt = await NotificationService.fetchUnreadCount();
                try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
              } catch (_) {}
            }
          } catch (e) {
            if (kDebugMode) debugPrint('Failed to confirm booking payment: $e');
            // If server reports no pending transaction (404) but this is a quote flow,
            // treat as success; otherwise, notify user non-fatally and continue.
            final emsg = e?.toString() ?? '';
            if (_isQuotePayment() || emsg.contains('404') || emsg.toLowerCase().contains('no pending')) {
              if (kDebugMode) debugPrint('Confirm returned 404/no-pending but treating as success for bookingId=$bookingId');
              if (mounted) AppNotification.showSuccess(context, 'Payment verified and booking is created.');
              try {
                final cnt = await NotificationService.fetchUnreadCount();
                try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
              } catch (_) {}
            } else {
              if (mounted) {
                AppNotification.showInfo(context, 'Payment verified but could not update booking status automatically.');
                try {
                  final cnt = await NotificationService.fetchUnreadCount();
                  try { app_state_notifier.AppStateNotifier.instance.setUnreadNotifications(cnt); } catch (_) {}
                } catch (_) {}
              }
            }
          }
        }
      }
    } else {
      if (kDebugMode) debugPrint('Background verification ultimately failed');
      // Optionally notify user non-blocking and leave booking as pending.
      if (mounted) AppNotification.showInfo(context, 'Payment verification is taking longer than expected. We will retry in the background.');
    }
  }

  // Call backend confirm endpoint to mark booking as verified/holding.
  Future<void> _confirmBookingPayment(String bookingId) async {
    final token = await TokenStorage.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/bookings/$bookingId/confirm-payment');
    final payload = <String, dynamic>{};
    if (_reference != null && _reference!.isNotEmpty) payload['reference'] = _reference;
    if (_lastVerifyResponse != null && _lastVerifyResponse!.isNotEmpty) payload['verifyResponse'] = _lastVerifyResponse;
    final resp = await http.post(uri, headers: headers, body: jsonEncode(payload)).timeout(_paymentRequestTimeout);
    if (kDebugMode) debugPrint('Confirm booking payment -> ${resp.statusCode} ${resp.body}');
    if (!(resp.statusCode >= 200 && resp.statusCode < 300)) {
      throw Exception('Confirm payment failed: ${resp.statusCode}');
    }
  }

  Future<dynamic> _openWebviewDialog(Widget page) async {
    if (!mounted) return null;
    try {
      final result = await showDialog<dynamic>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(insetPadding: const EdgeInsets.all(0), child: SizedBox(width: double.infinity, height: double.infinity, child: page)),
      );
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('openWebviewDialog error: $e');
      return null;
    }
  }

  Future<bool> _verifyPayment() async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/payments/verify');

      // Build robust reference/paymentId candidates
      String? refCandidate = _reference?.toString();
      final possibleRefs = <String?>[
        refCandidate,
        widget.payment['reference']?.toString(),
        widget.payment['ref']?.toString(),
        widget.payment['tx_ref']?.toString(),
        widget.payment['transaction_reference']?.toString(),
        widget.payment['authorization'] is Map ? (widget.payment['authorization']['reference']?.toString() ?? widget.payment['authorization']['tx_ref']?.toString()) : null,
      ];
      // Also try to extract from payment.raw or nested data
      try {
        if (widget.payment['data'] is Map) {
          final d = widget.payment['data'] as Map;
          possibleRefs.add(d['reference']?.toString());
          possibleRefs.add(d['tx_ref']?.toString());
        }
      } catch (_) {}

      // If authUrl is present, try parsing again for any remaining keys
      if ((possibleRefs.where((e) => e != null && e.isNotEmpty).isEmpty) && _authUrl != null && _authUrl!.isNotEmpty) {
        try {
          final u = Uri.tryParse(_authUrl!);
          if (u != null) {
            final q = u.queryParameters;
            final refKeys = ['reference', 'ref', 'tx_ref', 'trxref', 'transaction_reference', 'transaction', 'payment_reference'];
            for (final k in refKeys) {
              if (q.containsKey(k) && q[k] != null && q[k]!.isNotEmpty) {
                possibleRefs.add(q[k]);
              }
            }
          }
        } catch (_) {}
      }

      // pick the first non-empty candidate
      refCandidate = possibleRefs.firstWhere((e) => e != null && e.toString().trim().isNotEmpty, orElse: () => null)?.toString();

      String? paymentIdCandidate = (widget.payment['_id'] ?? widget.payment['paymentId'] ?? widget.payment['id'] ?? widget.payment['transactionId'])?.toString();

      final body = <String, dynamic>{};
      if (refCandidate != null && refCandidate.isNotEmpty) body['reference'] = refCandidate;
      if (paymentIdCandidate != null && paymentIdCandidate.isNotEmpty) body['paymentId'] = paymentIdCandidate;
      if (_email != null && _email!.isNotEmpty) body['email'] = _email;

      if (kDebugMode) debugPrint('Payment verify payload -> $body');

      // Try verification once, then if it fails and we can try an alternate key, retry
      final attemptVerify = (Map<String, dynamic> payload) async {
        try {
          final resp = await http.post(uri, headers: headers, body: jsonEncode(payload)).timeout(_paymentRequestTimeout);
          if (kDebugMode) debugPrint('Payment verify -> ${resp.statusCode} ${resp.body}');
          // capture last response for debugging
          try { _lastVerifyResponse = resp.body; } catch (_) { _lastVerifyResponse = null; }
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            try {
              final decoded = jsonDecode(resp.body);
              if (kDebugMode) debugPrint('Payment verify decoded -> $decoded');

              // Accept top-level success boolean
              if (decoded is Map && (decoded['success'] == true || decoded['ok'] == true)) {
                return true;
              }

              final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
              if (data is Map) {
                final dynamic statusRaw = (data['status'] ?? data['paymentStatus'] ?? data['paid'] ?? data['isPaid'] ?? data['state'] ?? data['statusText']);
                if (statusRaw != null) {
                  if (statusRaw is bool && statusRaw == true) return true;
                  final s = statusRaw.toString().toLowerCase();
                  final okValues = ['paid', 'success', 'completed', 'held', 'holding', 'authorized', 'successful', 'ok'];
                  for (final v in okValues) if (s.contains(v)) return true;
                }

                try {
                  final paymentNode = data['payment'] ?? data['paymentData'] ?? data['payment_response'] ?? data['authorization'];
                  if (paymentNode is Map) {
                    final pStatus = (paymentNode['status'] ?? paymentNode['paid'] ?? paymentNode['isPaid'] ?? paymentNode['paymentStatus']);
                    if (pStatus != null) {
                      if (pStatus is bool && pStatus == true) return true;
                      final s = pStatus.toString().toLowerCase();
                      final okValues = ['paid', 'success', 'completed', 'held', 'holding', 'authorized', 'successful', 'ok'];
                      for (final v in okValues) if (s.contains(v)) return true;
                    }
                  }
                } catch (_) {}
              }

              try {
                if (decoded is Map && decoded['message'] is String) {
                  final msg = decoded['message'].toString().toLowerCase();
                  final okWords = ['paid', 'success', 'completed', 'held', 'holding', 'authorized', 'successful'];
                  for (final w in okWords) if (msg.contains(w)) return true;
                }
              } catch (_) {}
            } catch (e) {
              if (kDebugMode) debugPrint('Payment verify parse error: $e');
            }
          }
          return false;
        } catch (e) {
          if (kDebugMode) debugPrint('Payment verify request error: $e');
          return false;
        }
      };

      bool ok = await attemptVerify(body);
      if (!ok) {
        final altRef = (widget.payment['authorization'] is Map) ? (widget.payment['authorization']['reference']?.toString() ?? widget.payment['authorization']['tx_ref']?.toString()) : null;
        if (altRef != null && altRef.isNotEmpty && altRef != refCandidate) {
          final retryBody = Map<String, dynamic>.from(body);
          retryBody['reference'] = altRef;
          if (kDebugMode) debugPrint('Retrying verification with altRef=$altRef');
          ok = await attemptVerify(retryBody);
        }
      }
      return ok;
    } catch (e) {
      if (kDebugMode) debugPrint('verify error: $e');
    }
    return false;
  }

  Future<Map<String, String?>?> _createBookingAfterPayment() async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final body = <String, dynamic>{};
      // Decide booking status: if this payment is for a quote, auto-accept the booking;
      // otherwise leave as pending (direct-hire needs artisan acceptance).
      try {
        String? qid;
        try { qid = widget.quote?['_id']?.toString() ?? widget.payment['quoteId']?.toString() ?? widget.payment['quote']?['_id']?.toString(); } catch (_) { qid = null; }
        String? bookingSource;
        try {
          bookingSource = (widget.payment['bookingSource'] ?? widget.payment['metadata'] is Map ? widget.payment['metadata']['bookingSource'] : null)?.toString();
        } catch (_) {
          bookingSource = null;
        }
        if ((qid != null && qid.isNotEmpty) || (bookingSource != null && bookingSource.toString().toLowerCase() == 'quote')) {
          body['status'] = 'accepted';
        } else {
          body['status'] = 'pending';
        }
      } catch (_) {
        try { body['status'] = 'pending'; } catch (_) {}
      }

      String? artisanId;
      try { artisanId = widget.booking?['artisanId']?.toString(); } catch (_) {}
      if (artisanId == null || artisanId.isEmpty) {
        try { artisanId = widget.quote?['artisanId']?.toString() ?? widget.quote?['userId']?.toString() ?? widget.quote?['artisan']?['_id']?.toString() ?? widget.quote?['artisanUser']?['_id']?.toString(); } catch (_) {}
      }
      if (artisanId == null || artisanId.isEmpty) {
        try {
          final meta = widget.payment['metadata'];
          if (meta is Map) {
            artisanId = (meta['artisanId'] ?? meta['artisan'] ?? meta['artisan_id'])?.toString();
          } else if (meta is String && meta.isNotEmpty) {
            try {
              final parsed = jsonDecode(meta);
              if (parsed is Map) artisanId = (parsed['artisanId'] ?? parsed['artisan'] ?? parsed['artisan_id'])?.toString();
            } catch (_) {}
          }
        } catch (_) {}
      }
      if (artisanId == null || artisanId.isEmpty) {
        try { artisanId = widget.payment['artisanId']?.toString() ?? widget.payment['artisan']?['_id']?.toString(); } catch (_) {}
      }
      // Final attempt: use helper that checks many nested locations
      if (artisanId == null || artisanId.isEmpty) {
        try { artisanId = _resolveArtisanUserId(); } catch (_) {}
      }
      // Also try the saved init request payload if it contained artisanId
      if ((artisanId == null || artisanId.isEmpty) && _initRequestPayload != null) {
        try {
          final cand = _initRequestPayload!['artisanId'] ?? (_initRequestPayload!['metadata'] is Map ? _initRequestPayload!['metadata']['artisanId'] : null);
          if (cand != null && cand.toString().isNotEmpty) artisanId = cand.toString();
        } catch (_) {}
      }
      if (artisanId != null && artisanId.isNotEmpty) body['artisanId'] = artisanId;

      try {
        if (_amount != null) body['price'] = _amount;
        else if (widget.booking?['price'] != null) body['price'] = widget.booking?['price'];
        else if (widget.payment['amount'] != null) body['price'] = widget.payment['amount'];
        else if (widget.payment['authorization']?['amount'] != null) body['price'] = widget.payment['authorization']?['amount'];
      } catch (_) {}

      try {
        var schedule = widget.booking?['schedule'] ?? widget.quote?['schedule'] ?? widget.payment['schedule'];
        if (schedule == null || (schedule is String && schedule.isEmpty)) schedule = DateTime.now().toUtc().toIso8601String();
        body['schedule'] = schedule;
      } catch (_) { body['schedule'] = DateTime.now().toUtc().toIso8601String(); }

      try { if (_email != null && _email!.isNotEmpty) body['email'] = _email; else if (widget.payment['customerEmail'] != null) body['email'] = widget.payment['customerEmail']; } catch (_) {}

      try { final qid = widget.quote?['_id'] ?? widget.payment['quoteId'] ?? widget.payment['quote']?['_id']; if (qid != null) body['acceptedQuote'] = qid; } catch (_) {}

      if (kDebugMode) debugPrint('Create booking payload: ' + jsonEncode(body));

      final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/bookings/hire');
      var resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
      if (kDebugMode) debugPrint('Create booking after payment -> status=${resp.statusCode}, body=${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(resp.body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map) {
            final id = data['_id']?.toString() ?? data['booking']?['_id']?.toString();
            final threadId = data['threadId']?.toString() ?? data['chat']?['_id']?.toString();
            if (id != null) {
              // Debug: log server response booking/thread ids to help trace null threadId issues
              try { if (kDebugMode) debugPrint('createBookingAfterPayment -> server returned bookingId=$id threadId=${threadId ?? '<null>'}'); } catch (_) {}
              return {'bookingId': id, 'threadId': threadId};
            }
          }
        } catch (e) { if (kDebugMode) debugPrint('Create booking parse error: $e'); }
      } else {
        // If 400 about artisanId and we have acceptedQuote, try to fetch quote to get artisanId then retry
        if (resp.statusCode == 400 && (resp.body?.toString().toLowerCase().contains('artisanid') ?? false) && body['acceptedQuote'] != null && (body['artisanId'] == null || body['artisanId'].toString().isEmpty)) {
          try {
            final qid = body['acceptedQuote'].toString();
            final fetched = await _fetchQuoteById(qid, headers);
            if (fetched != null) {
              final possible = (fetched['artisanId'] ?? fetched['artisan'] ?? fetched['artisanUser'] ?? fetched['artisan_user']);
              if (possible != null) body['artisanId'] = (possible is Map ? (possible['_id'] ?? possible['id']) : possible).toString();
              if (kDebugMode) debugPrint('Retrying create booking with artisanId=${body['artisanId']}');
              resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
              if (kDebugMode) debugPrint('Create booking retry -> status=${resp.statusCode}, body=${resp.body}');
              if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
                try {
                  final decoded = jsonDecode(resp.body);
                  final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
                  if (data is Map) {
                    final id = data['_id']?.toString() ?? data['booking']?['_id']?.toString();
                    final threadId = data['threadId']?.toString() ?? data['chat']?['_id']?.toString();
                    if (id != null) return {'bookingId': id, 'threadId': threadId};
                  }
                } catch (e) { if (kDebugMode) debugPrint('Create booking retry parse error: $e'); }
              }
            }
          } catch (e) { if (kDebugMode) debugPrint('Retry create booking error: $e'); }
        }
        if (kDebugMode) debugPrint('Create booking failed: ${resp.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Create booking error: $e');
    }
    return null;
  }

    // Poll the quote endpoint until the server webhook creates an associated booking.
    Future<Map<String, String?>?> _pollForBookingFromQuote(String? qid, {int maxAttempts = 6, Duration initialDelay = const Duration(seconds: 1)}) async {
    if (qid == null || qid.isEmpty) return null;
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      var attempt = 0;
      var delay = initialDelay;
      while (attempt < maxAttempts) {
        attempt += 1;
        try {
          final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/bookings?page=1&limit=50');
          final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
          if (kDebugMode) debugPrint('Poll bookings attempt $attempt for qid=$qid -> ${resp.statusCode} ${resp.body}');
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
            List items = [];
            if (data is List) items = data;
            else if (data is Map && data['items'] is List) items = data['items'];
            else if (data is Map && data['bookings'] is List) items = data['bookings'];

            for (final it in items) {
              try {
                if (it is Map) {
                  final accepted = (it['acceptedQuote'] ?? it['accepted_quote'] ?? it['booking']?['acceptedQuote'] ?? it['booking']?['accepted_quote'])?.toString();
                  final paymentStatus = (it['paymentStatus'] ?? it['booking']?['paymentStatus'])?.toString().toLowerCase();
                  if (accepted != null && accepted.isNotEmpty && accepted == qid) {
                    final id = (it['_id']?.toString() ?? it['id']?.toString() ?? (it['booking'] is Map ? (it['booking']['_id']?.toString() ?? it['booking']['id']?.toString()) : null));
                    final tid = (it['threadId']?.toString() ?? it['chat']?['_id']?.toString());
                    if (id != null && id.isNotEmpty) return {'bookingId': id, 'threadId': tid};
                  }
                  if (paymentStatus == 'paid') {
                    final accepted2 = (it['acceptedQuote'] ?? it['accepted_quote'] ?? it['booking']?['acceptedQuote'] ?? it['booking']?['accepted_quote'])?.toString();
                    if (accepted2 != null && accepted2.isNotEmpty && accepted2 == qid) {
                      final id = (it['_id']?.toString() ?? it['id']?.toString() ?? (it['booking'] is Map ? (it['booking']['_id']?.toString() ?? it['booking']['id']?.toString()) : null));
                      final tid = (it['threadId']?.toString() ?? it['chat']?['_id']?.toString());
                      if (id != null && id.isNotEmpty) return {'bookingId': id, 'threadId': tid};
                    }
                  }
                }
              } catch (_) {}
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error polling bookings for quote: $e');
        }
        await Future.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Top-level pollBookingsForQuote error: $e');
    }
    return null;
    }

    // Backwards-compatible wrapper: delegate to _pollForBookingFromQuote
    Future<Map<String, String?>?> _pollBookingsForQuote(String? qid, {int maxAttempts = 6, Duration initialDelay = const Duration(seconds: 1)}) async {
    return await _pollForBookingFromQuote(qid, maxAttempts: maxAttempts, initialDelay: initialDelay);
    }

  Future<void> _showAwaitingServerConfirmationBottomSheet(String quoteId) async {
    if (!mounted) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: FlutterFlowTheme.of(ctx).secondaryBackground, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Payment received', style: FlutterFlowTheme.of(ctx).titleLarge.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('We received your payment but are still waiting for the server to create the booking. This should complete shortly.', textAlign: TextAlign.center, style: FlutterFlowTheme.of(ctx).bodySmall),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: ElevatedButton(onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Retry polling once more with conservative attempts
                    try {
                      final polled = await _pollBookingsForQuote(quoteId, maxAttempts: 6, initialDelay: const Duration(seconds: 1));
                      if (polled != null) {
                        _bookingId = polled['bookingId'];
                        final thread = polled['threadId'];
                        await _showBookingCreatedBottomSheet(_bookingId!, thread, null, null, null);
                        return;
                      }
                      // still not found: inform user
                      AppNotification.showInfo(context, 'Payment received — awaiting server confirmation. Contact support if this takes too long.');
                    } catch (e) { if (kDebugMode) debugPrint('Retry poll error: $e'); }
                  }, child: const Text('Retry'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton(onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Open mailto or support flow
                    try { final uri = Uri.parse('mailto:support@rijhub.com?subject=Payment%20confirmation%20help&body=Quote%20id:%20$quoteId'); if (await canLaunchUrl(uri)) await launchUrl(uri); } catch (_) {}
                  }, child: const Text('Contact support'))),
                ])
              ]),
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('showAwaitingServerConfirmationBottomSheet error: $e');
    }
  }

  // Helper: check if this payment is for a quote
  bool _isQuotePayment() {
    try {
      if (widget.quote != null) return true;
      final p = widget.payment;
      if (p is Map) {
        final bs = p['bookingSource'] ?? (p['metadata'] is Map ? p['metadata']['bookingSource'] : null);
        if (bs != null && bs.toString().toLowerCase() == 'quote') return true;
        if (p['quoteId'] != null || p['quote'] != null) return true;
      }
      if (_initRequestPayload != null) {
        final bs2 = _initRequestPayload!['bookingSource'] ?? (_initRequestPayload!['metadata'] is Map ? _initRequestPayload!['metadata']['bookingSource'] : null);
        if (bs2 != null && bs2.toString().toLowerCase() == 'quote') return true;
        if (_initRequestPayload!['quoteId'] != null) return true;
      }
    } catch (_) {}
    return false;
  }

  // Accept a quote using the job-scoped accept endpoint as required by spec.
  // POST /api/jobs/:jobId/quotes/:quoteId/accept with { email }
  Future<bool> _acceptQuoteIfNeeded() async {
    try {
      final qid = widget.quote?['_id']?.toString() ?? widget.quote?['id']?.toString() ?? widget.quote?['quoteId']?.toString() ?? _quoteId;
      if (qid == null || qid.isEmpty) return false;
      // derive jobId from payloads
      String? jobId;
      try {
        jobId = widget.payment['jobId']?.toString() ?? widget.booking?['jobId']?.toString() ?? widget.quote?['jobId']?.toString();
        if (jobId == null) {
          final pj = widget.payment['job'];
          if (pj is Map) jobId = (pj['_id'] ?? pj['id'])?.toString();
        }
      } catch (_) { jobId = null; }
      if (jobId == null || jobId.isEmpty) return false;

      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/jobs/$jobId/quotes/$qid/accept');
      final body = <String, dynamic>{};
      if (_email != null && _email!.isNotEmpty) body['email'] = _email;
      if (kDebugMode) debugPrint('Accepting quote -> POST $uri body=$body');

      final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(_paymentRequestTimeout);
      if (kDebugMode) debugPrint('Accept quote response -> ${resp.statusCode} ${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final parsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final data = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
        try {
          if (data is Map) {
            // set server-provided payment node if present
            if (data['payment'] != null) {
              final p = data['payment'];
              if (p is Map) {
                _authUrl = _authUrl ?? (p['authorization_url'] ?? p['authorizationUrl'] ?? p['auth_url'])?.toString();
                _reference = _reference ?? (p['reference'] ?? p['ref'] ?? p['tx_ref'])?.toString();
              }
            }
            // try to capture returned quote id/booking id
            final bid = (data['booking'] is Map ? (data['booking']['_id'] ?? data['booking']['id']) : (data['bookingId'] ?? data['booking']?['_id'] ?? data['booking']?['id']))?.toString();
            if (bid != null && bid.isNotEmpty) _bookingId = bid;
            _quoteId = qid;
          }
        } catch (_) {}
        return true;
      }
      // unauthorized or not found
      if (resp.statusCode == 401) return false;
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('Accept quote error: $e');
    }
    return false;
  }

  // Poll a specific booking until its status/paymentStatus reflects acceptance/paid.
  Future<Map<String, dynamic>?> _pollBookingStatus(String bookingId, {int maxAttempts = 7, Duration initialDelay = const Duration(seconds: 1)}) async {
    if (bookingId == null || bookingId.isEmpty) return null;
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/bookings/$bookingId');

      var attempt = 0;
      var delay = initialDelay;
      Map<String, dynamic>? lastSeen;
      while (attempt < maxAttempts) {
        attempt += 1;
        try {
          final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
          if (kDebugMode) debugPrint('_pollBookingStatus attempt $attempt -> ${resp.statusCode} ${resp.body}');
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
            if (data is Map) {
              lastSeen = Map<String, dynamic>.from(data);
              final status = (data['status'] ?? data['booking']?['status'])?.toString().toLowerCase() ?? '';
              final paymentStatus = (data['paymentStatus'] ?? data['booking']?['paymentStatus'])?.toString().toLowerCase() ?? '';
              if (kDebugMode) debugPrint('_pollBookingStatus got status=$status paymentStatus=$paymentStatus');
              if (status.contains('await') || status == 'accepted' || paymentStatus == 'paid' || status == 'in-progress' || status == 'completed') {
                return data as Map<String, dynamic>;
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('_pollBookingStatus error: $e');
        }
        await Future.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
      return lastSeen;
    } catch (e) {
      if (kDebugMode) debugPrint('_pollBookingStatus top-level error: $e');
    }
    return null;
  }

  // Fetch thread id for a booking
  Future<String?> _fetchThreadIdForBooking(String bookingId) async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/chat/booking/$bookingId');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (kDebugMode) debugPrint('fetchThreadIdForBooking -> ${resp.statusCode} ${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        if (data is Map) {
          return (data['threadId']?.toString() ?? data['_id']?.toString());
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchThreadIdForBooking error: $e');
    }
    return null;
  }

  Future<void> _showBookingCreatedBottomSheet(String bookingId, String? threadId, String? jobTitle, String? bookingPrice, String? bookingDateTime) async {
    if (!mounted) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: FlutterFlowTheme.of(ctx).secondaryBackground, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Booking created', style: FlutterFlowTheme.of(ctx).titleLarge.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Your booking has been created successfully.', textAlign: TextAlign.center, style: FlutterFlowTheme.of(ctx).bodySmall),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () async {
                  Navigator.of(ctx).pop();
                  try { final rootNav = Navigator.of(context, rootNavigator: true); await rootNav.pushReplacement(MaterialPageRoute(builder: (_) => NavBarPage(initialPage: 'BookingPage', page: BookingPageWidget(bookingId: bookingId, threadId: threadId)))); } catch (_) {}
                }, child: const Text('View bookings'))
              ]),
            ),
          );
        },
      );
    } catch (e) { if (kDebugMode) debugPrint('showBookingCreatedBottomSheet error: $e'); }
  }

  Future<void> _showBookingFailedBottomSheet(String? jobTitle, String? bookingPrice, String? bookingDateTime) async {
    if (!mounted) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: FlutterFlowTheme.of(ctx).secondaryBackground, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Booking not created', style: FlutterFlowTheme.of(ctx).titleLarge.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                const SizedBox(height: 8),
                Text('We verified your payment but could not create the booking automatically. You can retry or contact support.', textAlign: TextAlign.center, style: FlutterFlowTheme.of(ctx).bodySmall),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: ElevatedButton(onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (_authUrl != null && _authUrl!.isNotEmpty) {
                      await _startInAppPayment();
                    } else {
                      await _initPaymentThenStart();
                    }
                  }, child: const Text('Retry payment'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton(onPressed: () { Navigator.of(ctx).pop(); }, child: const Text('Close'))),
                ])
              ]),
            ),
          );
        },
      );
    } catch (e) { if (kDebugMode) debugPrint('showBookingFailedBottomSheet error: $e'); }
  }

  Future<dynamic> _fetchQuoteById(String id, Map<String, String> headers) async {
    try {
      if (id == null || id.isEmpty) return null;
      // Try job-scoped
      String? jobId;
      try { jobId = widget.payment['jobId']?.toString() ?? widget.booking?['jobId']?.toString() ?? widget.quote?['jobId']?.toString(); } catch (_) { jobId = null; }
      if (jobId != null && jobId.isNotEmpty) {
        try {
          final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/jobs/$jobId/quotes/$id');
          final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
          if (kDebugMode) debugPrint('Fetch job-scoped quote $id -> ${resp.statusCode} ${resp.body}');
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            return decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          }
        } catch (e) { if (kDebugMode) debugPrint('Job-scoped fetch quote error: $e'); }
      }
      // fallback to generic
      try {
        final uri = Uri.parse('${_normalizeBaseUrl(API_BASE_URL)}/api/quotes/$id');
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
        if (kDebugMode) debugPrint('Fetch generic quote $id -> ${resp.statusCode} ${resp.body}');
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          return decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        }
      } catch (e) { if (kDebugMode) debugPrint('Generic fetch quote error: $e'); }
    } catch (e) { if (kDebugMode) debugPrint('Fetch quote by id unexpected error: $e'); }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final serviceTitle = widget.booking?['service'] ?? widget.quote?['title'] ?? widget.payment['service'] ?? 'Service';
    return WillPopScope(
      onWillPop: () async => !_blocking,
      child: Scaffold(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: Stack(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  TextButton.icon(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back), label: Text('Back', style: FlutterFlowTheme.of(context).bodyMedium)),
                ]),
                const SizedBox(height: 12),
                Text('Checkout', style: FlutterFlowTheme.of(context).titleLarge.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: FlutterFlowTheme.of(context).secondaryBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: FlutterFlowTheme.of(context).alternate.withAlpha(50))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(serviceTitle.toString(), style: FlutterFlowTheme.of(context).titleMedium.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Amount', style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText)),
                    const SizedBox(height: 6),
                    Text(_displayAmount(_amount), style: FlutterFlowTheme.of(context).titleLarge.copyWith(fontWeight: FontWeight.w800, color: FlutterFlowTheme.of(context).primary)),
                  ]),
                ),
                const Spacer(),
                Text('Payments are processed securely.', style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (!_blocking) ? () async {
                      if (_authUrl != null && _authUrl!.isNotEmpty) {
                        await _startInAppPayment();
                      } else {
                        await _initPaymentThenStart();
                      }
                    } : null,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: FlutterFlowTheme.of(context).primary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text((_authUrl != null && _authUrl!.isNotEmpty) ? 'Pay ${_displayAmount(_amount)}' : (_amount != null ? 'Initialize payment • ${_displayAmount(_amount)}' : 'No payment link'), style: FlutterFlowTheme.of(context).titleSmall.copyWith(color: FlutterFlowTheme.of(context).onPrimary)),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),

          // Verification/loading overlay
          if ((_state == _PaymentState.verifying) || (_loading && _blocking)) ...[
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    color: FlutterFlowTheme.of(context).secondaryBackground,
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(width: 6),
                        const CircularProgressIndicator(),
                        const SizedBox(width: 16),
                        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Verifying payment...', style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 6),
                          Text('Please wait while we confirm your transaction.', style: FlutterFlowTheme.of(context).bodySmall),
                        ]),
                        const SizedBox(width: 6),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],

        ]),
      ),
    );
  }
}
