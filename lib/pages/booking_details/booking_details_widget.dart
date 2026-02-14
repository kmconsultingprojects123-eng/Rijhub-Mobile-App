import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../services/token_storage.dart';
import '../../utils/auth_guard.dart';
import '../message_client/message_client_widget.dart';
import '../booking_page/booking_page_widget.dart';
import '../payment_init/payment_init_page_widget.dart';
import '../../utils/navigation_utils.dart';

class BookingDetailsWidget extends StatefulWidget {
  final String? bookingId;
  final String? threadId;
  final String? jobTitle;
  final String? bookingPrice;
  final String? bookingDateTime;
  final bool? success;
  final Map<String, dynamic>? paymentPayload;

  const BookingDetailsWidget({super.key, this.bookingId, this.threadId, this.jobTitle, this.bookingPrice, this.bookingDateTime, this.success, this.paymentPayload});

  static String routeName = 'bookingDetails';
  static String routePath = '/bookingDetails';

  @override
  State<BookingDetailsWidget> createState() => _BookingDetailsWidgetState();
}

class _BookingDetailsWidgetState extends State<BookingDetailsWidget> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _booking;
  String? _threadId;
  String? _jobTitle;
  String? _bookingPrice;
  String? _bookingDateTime;

  @override
  void initState() {
    super.initState();
    // Debug logging to confirm widget initialization and passed-in params
    try {
      debugPrint('🔵 === BOOKING DETAILS WIDGET INITIALIZED ===');
      debugPrint('🔵 Booking ID: ${widget.bookingId}');
      debugPrint('🔵 Thread ID: ${widget.threadId}');
      debugPrint('🔵 Job Title: ${widget.jobTitle}');
      debugPrint('🔵 Booking Price: ${widget.bookingPrice}');
      debugPrint('🔵 Booking DateTime: ${widget.bookingDateTime}');
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        debugPrint('🔵 BookingDetailsWidget frame rendered');
      } catch (_) {}
    });

    // Initialize optional context passed from caller
    _threadId = widget.threadId;
    _jobTitle = widget.jobTitle;
    _bookingPrice = widget.bookingPrice;
    _bookingDateTime = widget.bookingDateTime;
    if (widget.bookingId != null) {
      _fetchBooking();
    } else {
      // Handle case where bookingId is not provided
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _fetchBooking() async {
    setState(() { _loading = true; _error = false; });
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final uri = Uri.parse('$API_BASE_URL/api/bookings/${widget.bookingId}');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      if (resp.statusCode >=200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        if (data is Map) {
          try { debugPrint('🔵 Booking fetched from API (raw): ${resp.body}'); } catch (_) {}
           setState(() {
             _booking = Map<String, dynamic>.from(data);
             try { debugPrint('🔵 Booking parsed id: ${_booking?['_id'] ?? _booking?['id'] ?? widget.bookingId}'); } catch (_) {}
             // Try to find thread id in common places
             _threadId = data['threadId']?.toString() ?? data['chat']?['_id']?.toString();
             if (_threadId == null) {
               try {
                 final meta = data['metadata'];
                 if (meta is Map) _threadId = (meta['threadId'] ?? meta['thread'] ?? meta['chatId'])?.toString();
               } catch (_) {}
             }
             _loading = false;
           });
           return;
         }
       }
       // Not found or error
       setState(() { _error = true; _loading = false; });
     } catch (e) {
       if (mounted) setState(() { _error = true; _loading = false; });
     }
   }

  String _displayAmount(dynamic a) {
    try {
      if (a == null) return '-';
      if (a is num) return '₦' + NumberFormat('#,##0', 'en_US').format(a);
      final n = num.tryParse(a.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (n != null) return '₦' + NumberFormat('#,##0', 'en_US').format(n);
      return a.toString();
    } catch (_) { return a.toString(); }
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // If we failed to fetch the booking from the backend, show a helpful
    // fallback that uses any minimal data passed in via constructor (bookingId,
    // jobTitle, bookingPrice, bookingDateTime). This prevents the user from
    // being stuck on a blank/error screen when navigation succeeded but the
    // backend call failed (e.g., transient auth/token issue).
    if (_booking == null) {
      // Build a lightweight summary using passed-in values
      final title = widget.jobTitle ?? 'Booking';
      final schedule = widget.bookingDateTime ?? '-';
      final price = _displayAmount(widget.bookingPrice ?? '-');
      final statusText = widget.success == null ? 'Pending' : (widget.success! ? 'Successful' : 'Failed');

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Schedule', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(schedule, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))])),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Price', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(price, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))])
          ]),
          const SizedBox(height: 16),
          Row(children: [Text('Status: ', style: Theme.of(context).textTheme.bodyMedium), Text(statusText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 12),
          if ((widget.bookingId ?? '').isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Booking ID', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(widget.bookingId!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 20),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _fetchBooking,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry fetching'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                try {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingPageWidget()));
                } catch (_) {}
              },
              icon: const Icon(Icons.list_alt),
              label: const Text('Go to Bookings'),
            ),
            const SizedBox(width: 12),
            if (widget.paymentPayload != null) ElevatedButton.icon(
              onPressed: () async {
                if (!await ensureSignedInForAction(context)) return;
                try {
                  final pm = Map<String, dynamic>.from(widget.paymentPayload!);
                  try {
                    // preserve or set bookingSource if quote info is present
                    final hasQuote = (pm['quoteId'] != null || widget.bookingId != null || pm['acceptedQuote'] != null);
                    if (hasQuote) {
                      final meta = pm['metadata'] is Map ? Map<String, dynamic>.from(pm['metadata']) : <String, dynamic>{};
                      meta['bookingSource'] = meta['bookingSource'] ?? 'quote';
                      pm['metadata'] = meta;
                      pm['bookingSource'] = pm['bookingSource'] ?? 'quote';
                    }
                  } catch (_) {}
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentInitPageWidget(payment: pm)));
                } catch (_) {}
              },
              icon: const Icon(Icons.payment),
              label: const Text('Retry Payment'),
            ),
          ]),
        ]),
      );
    }

    final b = _booking!;
    final title = (b['service'] ?? b['serviceTitle'] ?? b['title'])?.toString() ?? 'Booking';
    final schedule = (() {
      final cand = b['schedule'] ?? b['dateTime'] ?? b['createdAt'];
      if (cand == null) return '-';
      try {
        final dt = DateTime.tryParse(cand.toString());
        if (dt != null) return DateFormat.yMMMd().add_jm().format(dt);
      } catch (_) {}
      return cand.toString();
    })();
    final price = _displayAmount(b['price'] ?? b['amount'] ?? b['total'] ?? _bookingPrice);
    final status = (b['status'] ?? b['paymentStatus'] ?? '');
    final String artisan = (() {
      try {
        final a = b['artisanUser'] ?? b['artisan'] ?? b['artisanId'];
        if (a is Map) return (a['name'] ?? a['fullName'] ?? '').toString();
        if (a is String) return a.toString();
      } catch (_) {}
      return '';
    })();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Schedule', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(schedule, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))])),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Price', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(price, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))])
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Text('Status: ', style: Theme.of(context).textTheme.bodyMedium),
          Text(status?.toString() ?? '-', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))
        ]),
        const SizedBox(height: 12),
        if (artisan.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Artisan', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height:6), Text(artisan, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))]),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () async {
            if (!await ensureSignedInForAction(context)) return;
            // Open chat — pass context information so the chat screen can initialize quickly
            try {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageClientWidget(
                bookingId: widget.bookingId,
                threadId: _threadId,
                jobTitle: _jobTitle ?? title,
                bookingPrice: _bookingPrice ?? price,
                bookingDateTime: _bookingDateTime ?? schedule,
              )));
            } catch (_) {}
          },
          icon: const Icon(Icons.message),
          label: const Text('Chat with Artisan'),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            // Navigate to the bookings list/page
            try {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingPageWidget()));
            } catch (_) {
              // fallback: do nothing
            }
          },
          icon: const Icon(Icons.list_alt),
          label: const Text('Go to Bookings'),
        ),
        if (widget.success != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.success! ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.success! ? Colors.green : Colors.red),
            ),
            child: Row(children: [
              Icon(widget.success! ? Icons.check_circle : Icons.error, color: widget.success! ? Colors.green : Colors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.success! ? 'Operation successful!' : 'Operation failed. Please try again.', style: Theme.of(context).textTheme.bodyMedium)),
              if (widget.paymentPayload != null) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    if (!await ensureSignedInForAction(context)) return;
                    // Navigate to payment initialization page (retry) - PaymentInitPageWidget expects 'payment'
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentInitPageWidget(payment: widget.paymentPayload!)));
                  },
                  child: const Text('Retry Payment'),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    try { debugPrint('🔵 BookingDetailsWidget.build called; bookingId=${widget.bookingId}'); } catch (_) {}
     return Scaffold(
       appBar: AppBar(title: const Text('Booking Details')),
       body: SafeArea(child: _buildContent()),
     );
   }
}
