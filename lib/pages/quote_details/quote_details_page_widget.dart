import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/token_storage.dart';
import '../../api_config.dart';
import 'package:rijhub/pages/payment_init/payment_init_page_widget.dart';

class QuoteDetailsPageWidget extends StatefulWidget {
  final Map<String, dynamic> quote;
  const QuoteDetailsPageWidget({super.key, required this.quote});

  @override
  State<QuoteDetailsPageWidget> createState() => _QuoteDetailsPageWidgetState();
}

class _QuoteDetailsPageWidgetState extends State<QuoteDetailsPageWidget> {
  bool _actionInProgress = false;
  // Fetched quote details (if we can fetch a richer representation from server)
  Map<String, dynamic>? _quoteDetails;
  bool _loadingQuote = false;

  @override
  void initState() {
    super.initState();
    // owner detection removed (unused in UI)
    // Try to fetch the authoritative quote record from server by id so the UI
    // shows the most up-to-date details.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchQuoteDetailsIfNeeded());
  }

  Future<void> _fetchQuoteDetailsIfNeeded() async {
    try {
      final qid = widget.quote['_id']?.toString() ?? widget.quote['id']?.toString() ?? widget.quote['quoteId']?.toString();
      if (qid == null || qid.isEmpty) return;
      // Try to use booking-scoped endpoint (documented in API_DOCS) if we have bookingId
      final bookingId = widget.quote['bookingId']?.toString() ?? (widget.quote['booking'] is Map ? (widget.quote['booking']['_id']?.toString() ?? widget.quote['booking']['id']?.toString()) : null);
      if (_loadingQuote) return;
      setState(() => _loadingQuote = true);

      final token = await TokenStorage.getToken();
      final headers = <String,String>{'Content-Type':'application/json'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      // If we have bookingId, the documented endpoint `GET /api/bookings/:id/quotes/details`
      // returns populated quotes and booking information. Try that first and find the matching quote.
      if (bookingId != null && bookingId.isNotEmpty) {
        try {
          final listUri = Uri.parse('$API_BASE_URL/api/bookings/$bookingId/quotes/details');
          if (kDebugMode) debugPrint('Fetching booking-scoped quotes -> $listUri');
          final listResp = await http.get(listUri, headers: headers).timeout(const Duration(seconds: 8));
          if (kDebugMode) debugPrint('Booking quotes resp -> ${listResp.statusCode}');
          if (listResp.statusCode >= 200 && listResp.statusCode < 300 && listResp.body.isNotEmpty) {
            final parsed = jsonDecode(listResp.body);
            final listData = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
            if (listData is List) {
              for (final item in listData) {
                try {
                  if (item is Map) {
                    final id = item['_id']?.toString() ?? item['id']?.toString();
                    if (id != null && id == qid) {
                      setState(() => _quoteDetails = Map<String, dynamic>.from(item));
                      return;
                    }
                  }
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Booking-scoped quotes fetch failed: $e');
          // fall through to single-quote fetch
        }
      }

      // Fallback: server might expose a job-scoped single-quote endpoint or a
      // booking-scoped single quote. Try job-scoped single-quote path
      // `/api/jobs/:jobId/quotes/:quoteId` before giving up to avoid calling
      // unsupported generic `/api/quotes/:id` routes.
      String? jobIdFallback;
      try {
        jobIdFallback = widget.quote['jobId']?.toString() ?? (widget.quote['job'] is Map ? ((widget.quote['job']['_id'] ?? widget.quote['job']['id'])?.toString()) : null);
      } catch (_) { jobIdFallback = null; }
      if (jobIdFallback != null && jobIdFallback.isNotEmpty) {
        try {
          final uri = Uri.parse('${API_BASE_URL.replaceAll(RegExp(r'/+\$'), '')}/api/jobs/$jobIdFallback/quotes/$qid');
          if (kDebugMode) debugPrint('Fetching job-scoped quote -> $uri');
          final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
          if (kDebugMode) debugPrint('Fetch job-scoped quote resp -> ${resp.statusCode}');
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
            if (data is Map) {
              setState(() => _quoteDetails = Map<String, dynamic>.from(data));
              return;
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Job-scoped single-quote fetch failed: $e');
        }
      }
      // If job-scoped route isn't available, give up — do not call generic /api/quotes/:id
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching quote details: $e');
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  Future<void> _acceptAndPay() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final q = widget.quote;
      // determine amount
      dynamic amt = q['total'] ?? q['amount'] ?? q['price'];
      if (amt == null) amt = q['items'] is List ? q['items'].fold(0, (p, e) {
        try {
          if (e is Map) return p + (num.tryParse((e['price'] ?? e['amount'] ?? e['cost'] ?? 0).toString()) ?? 0);
          return p;
        } catch (_) { return p; }
      }) : null;

      num? amountNum;
      if (amt is num) amountNum = amt;
      else if (amt != null) amountNum = num.tryParse(amt.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));

      final paymentMap = <String, dynamic>{};
      if (amountNum != null) paymentMap['amount'] = amountNum;
      paymentMap['currency'] = 'NGN';
      try {
        paymentMap['artisanId'] = paymentMap['artisanId']
            ?? (widget.quote['artisanId'] ?? (widget.quote['artisan'] is Map ? (widget.quote['artisan']['_id'] ?? widget.quote['artisan']['id']) : null) ?? widget.quote['userId']);
      } catch (_) {}
      // Explicitly mark this payment as coming from a quote so the server
      // (and PaymentInitPageWidget) can auto-accept bookings for quote flows.
      try {
        // preserve existing metadata if present
        final meta = paymentMap['metadata'] is Map ? Map<String, dynamic>.from(paymentMap['metadata']) : <String, dynamic>{};
        meta['bookingSource'] = meta['bookingSource'] ?? 'quote';
        paymentMap['metadata'] = meta;
        // also set top-level bookingSource for easier access in some code paths
        paymentMap['bookingSource'] = paymentMap['bookingSource'] ?? 'quote';
      } catch (_) {}

      // pass quote as-is so PaymentInitPageWidget can inspect it
      if (!mounted) return;

      // Try to extract bookingId from quote if present so the payment flow
      // can prefer booking-scoped endpoints (API: /api/bookings/:id/quotes/:quoteId/accept)
      String? bookingId;
      String? jobId;
      try {
        bookingId = widget.quote['bookingId']?.toString() ??
            (widget.quote['booking'] is Map ? ((widget.quote['booking']['_id'] ?? widget.quote['booking']['id'])?.toString()) : null);
        // Also try to extract jobId so PaymentInit can use job-scoped endpoints when bookingId is not present
        jobId = widget.quote['jobId']?.toString() ?? (widget.quote['job'] is Map ? ((widget.quote['job']['_id'] ?? widget.quote['job']['id'])?.toString()) : null) ?? widget.quote['jobId']?.toString();
      } catch (_) { bookingId = null; }

      if (bookingId != null && bookingId.isNotEmpty) {
        paymentMap['bookingId'] = bookingId;
      }
      if (jobId != null && jobId.isNotEmpty) {
        paymentMap['jobId'] = jobId;
      }

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentInitPageWidget(payment: paymentMap, booking: bookingId != null ? {'_id': bookingId} : null, quote: q),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to initiate payment: $e')));
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _showArtisanProfileSheet(Map<String, dynamic> artisan) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    // Resolve an id if possible
    String? resolvedId;
    try {
      resolvedId = artisan['_id']?.toString() ?? artisan['id']?.toString() ?? artisan['artisanId']?.toString() ?? artisan['userId']?.toString();
      if ((resolvedId == null || resolvedId.isEmpty) && artisan['user'] is Map) {
        resolvedId = (artisan['user']['_id'] ?? artisan['user']['id'])?.toString();
      }
    } catch (_) {
      resolvedId = null;
    }

    Future<Map<String, dynamic>?> _fetchArtisan(String? id) async {
      if (id == null || id.isEmpty) return null;
      try {
        final token = await TokenStorage.getToken();
        final headers = <String, String>{'Accept': 'application/json'};
        if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
        final base = API_BASE_URL.replaceAll(RegExp(r'/+\$'), '');
        final uri = Uri.parse('$base/api/artisans/$id');
        if (kDebugMode) debugPrint('Fetching artisan profile -> $uri');
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
          final body = jsonDecode(resp.body);
          final data = body is Map ? (body['data'] ?? body) : body;
          if (data is Map) return Map<String, dynamic>.from(data.cast<String, dynamic>());
        }
      } catch (e) {
        if (kDebugMode) debugPrint('fetch artisan failed: $e');
      }
      return null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24.0))),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
            boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.4 : 0.2), blurRadius: 24, offset: const Offset(0, -4))],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + (isSmallScreen ? 16 : 20),
              left: isSmallScreen ? 16 : 20,
              right: isSmallScreen ? 16 : 20,
              top: 16,
            ),
            child: SafeArea(
              top: false,
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _fetchArtisan(resolvedId),
                builder: (c, snap) {
                  final loading = snap.connectionState == ConnectionState.waiting;
                  final fetched = snap.hasData && snap.data != null;
                  final display = fetched ? snap.data! : Map<String, dynamic>.from(artisan);

                  final name = (display['name'] ?? display['fullName'] ?? display['username'] ?? 'Unknown').toString();
                  final email = display['email']?.toString() ?? '';
                  final phone = display['phone']?.toString() ?? display['mobile']?.toString() ?? '';
                  final about = (display['about'] ?? display['description'] ?? display['bio'])?.toString() ?? '';
                  String? profileImage;
                  try {
                    if (display['profileImage'] is String && display['profileImage'].toString().isNotEmpty) profileImage = display['profileImage'].toString();
                    else if (display['profileImage'] is Map) profileImage = display['profileImage']['url']?.toString() ?? display['profileImage']['path']?.toString();
                    else if (display['avatar'] is String) profileImage = display['avatar']?.toString();
                    else if (display['user'] is Map) profileImage = (display['user']['profileImage'] ?? display['user']['avatar'])?.toString();
                  } catch (_) {}

                  // simple portfolio extraction
                  List<String> portfolioImages = [];
                  try {
                    if (display['portfolio'] is List) {
                      for (final p in (display['portfolio'] as List)) {
                        if (p is String && p.isNotEmpty) portfolioImages.add(p);
                        else if (p is Map) {
                          final url = p['url'] ?? p['image'] ?? p['src'];
                          if (url is String && url.isNotEmpty) portfolioImages.add(url);
                        }
                      }
                    }
                    if (portfolioImages.isEmpty && display['images'] is List) {
                      for (final it in (display['images'] as List)) {
                        if (it is String && it.isNotEmpty) portfolioImages.add(it);
                        else if (it is Map && it['url'] is String) portfolioImages.add(it['url']);
                      }
                    }
                  } catch (_) {}

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Container(width: isSmallScreen ? 36 : 40, height: 4, decoration: BoxDecoration(color: isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(radius: isSmallScreen ? 28 : 34, backgroundImage: profileImage != null ? NetworkImage(profileImage) as ImageProvider : null, backgroundColor: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6), child: profileImage == null ? Icon(Icons.person_outline, size: isSmallScreen ? 28 : 32, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)) : null),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(fontSize: isSmallScreen ? 18 : 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF111827))),
                              const SizedBox(height: 6),
                              if (email.isNotEmpty) Text(email, style: TextStyle(color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))),
                            ])),
                            IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: Icon(Icons.close_rounded, size: isSmallScreen ? 20 : 24, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ... (loading
                            ? [
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ]
                            : [
                                if (about.isNotEmpty) ...[
                                  Text('About', style: TextStyle(fontSize: isSmallScreen ? 14 : 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF111827))),
                                  const SizedBox(height: 8),
                                  Text(about, style: TextStyle(color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))),
                                  const SizedBox(height: 12),
                                ],
                                if (portfolioImages.isNotEmpty) ...[
                                  Text('Portfolio', style: TextStyle(fontSize: isSmallScreen ? 15 : 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF111827))),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: isSmallScreen ? 88 : 120,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemBuilder: (c, i) {
                                        final src = portfolioImages[i];
                                        return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(src, width: isSmallScreen ? 120 : 160, height: isSmallScreen ? 88 : 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey, width: isSmallScreen ? 120 : 160, height: isSmallScreen ? 88 : 120)));
                                      },
                                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                                      itemCount: portfolioImages.length,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (phone.isNotEmpty || email.isNotEmpty) ...[
                                  Container(
                                    decoration: BoxDecoration(color: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.all(12),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      if (phone.isNotEmpty) _buildDetailRow(icon: Icons.phone_outlined, label: 'Phone', value: phone, isDark: isDark, isSmallScreen: isSmallScreen),
                                      if (email.isNotEmpty) ...[const SizedBox(height: 8), _buildDetailRow(icon: Icons.email_outlined, label: 'Email', value: email, isDark: isDark, isSmallScreen: isSmallScreen)],
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                // Bottom 'Close' button removed per request. Use header close icon to dismiss the sheet.
                                const SizedBox(height: 12),
                              ]),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    required bool isSmallScreen,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: isSmallScreen ? 16 : 18,
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 13,
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 15,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ffTheme = FlutterFlowTheme.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;

    // Prefer server-fetched quote details when available
    final q = _quoteDetails ?? widget.quote;
    final artisan = q['artisanUser'] ?? q['artisan'] ?? q['user'] ?? <String, dynamic>{};
    final name = (artisan['name'] ?? artisan['fullName'] ?? 'Unknown').toString();
    final email = (artisan['email'] ?? '')?.toString() ?? '';
    final qId = q['_id'] ?? q['id'] ?? q['quoteId'];

    // Resolve amount robustly: check common keys and nested containers
    dynamic _resolveAmount(Map<String, dynamic>? src) {
      if (src == null) return null;
      final candidates = ['total', 'amount', 'price', 'totalAmount', 'grandTotal', 'grand_total', 'total_price', 'quoteAmount', 'quote_amount', 'cost', 'value'];
      for (final k in candidates) {
        try {
          if (src.containsKey(k) && src[k] != null) return src[k];
        } catch (_) {}
      }
      // Try common nested sections
      final parents = ['quote', 'data', 'payment', 'cost', 'order', 'attributes'];
      for (final p in parents) {
        try {
          if (src[p] is Map) {
            final nested = src[p] as Map<String, dynamic>;
            for (final k in candidates) {
              if (nested.containsKey(k) && nested[k] != null) return nested[k];
            }
          }
        } catch (_) {}
      }
      return null;
    }

    num? _parseToNum(dynamic v) {
      try {
        if (v == null) return null;
        if (v is num) return v;
        if (v is String) {
          return num.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), ''));
        }
        if (v is Map) {
          final cand = v['amount'] ?? v['value'] ?? v['total'] ?? v['price'];
          return _parseToNum(cand);
        }
        return num.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      } catch (_) {
        return null;
      }
    }

    final resolvedRaw = _resolveAmount(q);
    num? amountNum = _parseToNum(resolvedRaw);
    // fallback: sum items
    if (amountNum == null) {
      try {
        if (q['items'] is List && (q['items'] as List).isNotEmpty) {
          num sum = 0;
          for (final it in (q['items'] as List)) {
            try {
              if (it is Map) {
                final p = it['price'] ?? it['amount'] ?? it['cost'] ?? it['value'];
                final pn = _parseToNum(p);
                if (pn != null) sum += pn;
              }
            } catch (_) {}
          }
          if (sum > 0) amountNum = sum;
        }
      } catch (_) {}
    }

    String formattedAmount;
    if (amountNum != null) {
      formattedAmount = '₦${amountNum.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
    } else {
      formattedAmount = '₦0';
    }

    // Extract additional quote details (note, service/schedule, created/expiry, booking address)
    final String note = (q['note'] ?? q['notes'] ?? q['description'] ?? q['details'] ?? q['message'] ?? q['remarks'])?.toString() ?? '';

    final dynamic serviceDateRaw = q['serviceDate'] ?? q['date'] ?? q['schedule'] ?? q['scheduledAt'] ?? q['startDate'] ?? q['start_time'];
    String? serviceDate;
    try {
      if (serviceDateRaw is String && serviceDateRaw.isNotEmpty) serviceDate = serviceDateRaw;
      else if (serviceDateRaw is num) serviceDate = DateTime.fromMillisecondsSinceEpoch(serviceDateRaw.toInt()).toLocal().toString();
      else if (serviceDateRaw != null) serviceDate = serviceDateRaw.toString();
    } catch (_) { serviceDate = serviceDateRaw?.toString(); }

    final dynamic createdAtRaw = q['createdAt'] ?? q['created_at'] ?? q['created'];
    String? createdAt;
    try { if (createdAtRaw is String) createdAt = createdAtRaw; else if (createdAtRaw is num) createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw.toInt()).toLocal().toString(); else if (createdAtRaw != null) createdAt = createdAtRaw.toString(); } catch (_) { createdAt = createdAtRaw?.toString(); }

    final dynamic expiresAtRaw = q['expiresAt'] ?? q['expiry'] ?? q['expires_at'] ?? q['validTill'];
    String? expiresAt;
    try { if (expiresAtRaw is String) expiresAt = expiresAtRaw; else if (expiresAtRaw is num) expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtRaw.toInt()).toLocal().toString(); else if (expiresAtRaw != null) expiresAt = expiresAtRaw.toString(); } catch (_) { expiresAt = expiresAtRaw?.toString(); }

    // Booking/address info (if present)
    String bookingAddress = '';
    try {
      final b = q['booking'] ?? q['bookingInfo'] ?? q['bookingDetails'];
      if (b is Map) {
        bookingAddress = (b['address'] ?? b['location'] ?? b['venue'] ?? b['addressLine'] ?? b['address_line'] ?? b['street'])?.toString() ?? '';
      }
    } catch (_) {}

    // Try to extract profile image for artisan (used in the Artisan card)
    String? profileImage;
    try {
      if (artisan['profileImage'] is String && artisan['profileImage'].toString().isNotEmpty) {
        profileImage = artisan['profileImage'].toString();
      } else if (artisan['profileImage'] is Map) {
        profileImage = artisan['profileImage']['url']?.toString() ?? artisan['profileImage']['path']?.toString();
      } else if (artisan['avatar'] is String) {
        profileImage = artisan['avatar']?.toString();
      } else if (artisan['user'] is Map) {
        profileImage = (artisan['user']['profileImage'] ?? artisan['user']['avatar'])?.toString();
      }
    } catch (_) {}

    return Scaffold(
      backgroundColor: ffTheme.primaryBackground,
      appBar: AppBar(
        backgroundColor: ffTheme.secondaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : const Color(0xFF111827),
            size: isSmallScreen ? 20 : 24,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Quote Details',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quote ID Card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: ffTheme.secondaryBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ffTheme.alternate,
                      width: 1,
                    ),
                  ),
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quote Reference',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          color: ffTheme.secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        qId?.toString() ?? 'N/A',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: ffTheme.primaryText,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Artisan Card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: ffTheme.secondaryBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ffTheme.alternate,
                      width: 1,
                    ),
                  ),
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: isSmallScreen ? 60 : 72,
                        height: isSmallScreen ? 60 : 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.primaryColor.withAlpha((0.2 * 255).round()),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: isSmallScreen ? 28 : 34,
                          backgroundImage: profileImage != null && profileImage.isNotEmpty ? NetworkImage(profileImage) as ImageProvider : null,
                          backgroundColor: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                          child: profileImage == null || profileImage.isEmpty
                              ? Icon(
                            Icons.person_outline,
                            size: isSmallScreen ? 28 : 32,
                            color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                          )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Artisan',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 18 : 20,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF111827),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 13 : 14,
                                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Amount Card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: ffTheme.secondaryBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ffTheme.alternate,
                      width: 1,
                    ),
                  ),
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quote Amount',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          color: ffTheme.secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formattedAmount,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 28 : 32,
                          fontWeight: FontWeight.w700,
                          color: ffTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is the total amount for the quoted service',
                        style: TextStyle(fontSize: isSmallScreen ? 12 : 13, color: ffTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Quote Items if available
                if (q['items'] is List && (q['items'] as List).isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: ffTheme.secondaryBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ffTheme.alternate,
                        width: 1,
                      ),
                    ),
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Items Breakdown',
                          style: TextStyle(fontSize: isSmallScreen ? 15 : 16, fontWeight: FontWeight.w600, color: ffTheme.primaryText),
                        ),
                        const SizedBox(height: 12),
                        ...(q['items'] as List).map<Widget>((item) {
                          final itemName = (item['name'] ?? item['description'] ?? 'Item').toString();
                          final itemPrice = (item['price'] ?? item['amount'] ?? 0).toString();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    itemName,
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 14 : 15,
                                      color: isDark ? Colors.white : const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                                Text(
                                  '₦$itemPrice',
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 14 : 15,
                                    fontWeight: FontWeight.w600,
                                    color: theme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Status if available
                if (q['status'] != null) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: ffTheme.secondaryBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ffTheme.alternate,
                        width: 1,
                      ),
                    ),
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(fontSize: isSmallScreen ? 14 : 15, fontWeight: FontWeight.w600, color: ffTheme.primaryText),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStatusColor(q['status'].toString(), isDark),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            q['status'].toString().toUpperCase(),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 12,
                              fontWeight: FontWeight.w600,
                              color: ffTheme.primaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // (Additional quote details variables are defined above in build scope.)
                // Try to extract profile image for artisan (used in the Artisan card) is handled in build scope above.

                // Render details if available
                if (note.isNotEmpty || serviceDate != null || createdAt != null || expiresAt != null || bookingAddress.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: ffTheme.secondaryBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ffTheme.alternate,
                        width: 1,
                      ),
                    ),
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Details', style: TextStyle(fontSize: isSmallScreen ? 15 : 16, fontWeight: FontWeight.w600, color: ffTheme.primaryText)),
                        const SizedBox(height: 8),
                        if (note.isNotEmpty) ...[
                          Text('Note', style: TextStyle(fontSize: isSmallScreen ? 13 : 14, color: ffTheme.secondaryText, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          Text(note, style: TextStyle(color: ffTheme.primaryText)),
                          const SizedBox(height: 8),
                        ],
                        if (serviceDate != null) ...[
                          _buildDetailRow(icon: Icons.schedule_outlined, label: 'Service Date', value: serviceDate!, isDark: isDark, isSmallScreen: isSmallScreen),
                          const SizedBox(height: 8),
                        ],
                        if (bookingAddress.isNotEmpty) ...[
                          _buildDetailRow(icon: Icons.location_on_outlined, label: 'Address', value: bookingAddress, isDark: isDark, isSmallScreen: isSmallScreen),
                          const SizedBox(height: 8),
                        ],
                        if (createdAt != null) ...[
                          _buildDetailRow(icon: Icons.calendar_today_outlined, label: 'Created', value: createdAt!, isDark: isDark, isSmallScreen: isSmallScreen),
                          const SizedBox(height: 6),
                        ],
                        if (expiresAt != null) ...[
                          _buildDetailRow(icon: Icons.hourglass_bottom_outlined, label: 'Expires', value: expiresAt!, isDark: isDark, isSmallScreen: isSmallScreen),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ]
                else
                  const SizedBox(height: 24),

                // Spacer
                SizedBox(height: isSmallScreen ? 20 : 32),

                // Action Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _showArtisanProfileSheet(artisan),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ffTheme.primaryText,
                          side: BorderSide(color: ffTheme.alternate),
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 16, horizontal: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: isSmallScreen ? 18 : 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'View Artisan Profile',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 14 : 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _actionInProgress ? null : _acceptAndPay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ffTheme.primary,
                          foregroundColor: ffTheme.onPrimary,
                          padding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 14 : 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _actionInProgress
                            ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(ffTheme.onPrimary),
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.payment_outlined,
                              size: isSmallScreen ? 18 : 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Accept & Pay',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 15 : 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B); // Amber
      case 'accepted':
      case 'approved':
        return const Color(0xFF10B981); // Green
      case 'rejected':
      case 'declined':
        return const Color(0xFFEF4444); // Red
      case 'completed':
        return const Color(0xFF8B5CF6); // Violet
      default:
        return isDark ? const Color(0xFF4B5563) : const Color(0xFF6B7280);
    }
  }
}
