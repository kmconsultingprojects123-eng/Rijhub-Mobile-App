import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../services/token_storage.dart';
import '../quote_details/quote_details_page_widget.dart';

class ApplicantsPage extends StatefulWidget {
  final String jobId;
  final Color primaryColor;

  const ApplicantsPage({super.key, required this.jobId, required this.primaryColor});

  @override
  State<ApplicantsPage> createState() => _ApplicantsPageState();
}

class _ApplicantsPageState extends State<ApplicantsPage> {
   Future<List<Map<String, dynamic>>> _fetchJobQuotes() async {
    final token = await TokenStorage.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$API_BASE_URL/api/jobs/${widget.jobId}/quotes'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) throw Exception('Failed to load applicants');

    final body = jsonDecode(response.body);
    final data = body['data'] ?? body['quotes'] ?? body;
    if (data is! List) return [];

    // Convert to mutable maps and attempt to enrich each quote with detailed data
    final rawQuotes = List<Map<String, dynamic>>.from(
      data.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}),
    );

    // Fetch details for each quote in parallel but safely
    final enrichedFutures = rawQuotes.map((q) => _fetchQuoteDetailsAndMerge(q, token)).toList();
    final enriched = await Future.wait(enrichedFutures);
    return enriched;
  }

  // Try to fetch richer detail for a single quote. Merges server response into the original.
  Future<Map<String, dynamic>> _fetchQuoteDetailsAndMerge(Map<String, dynamic> quote, String token) async {
    try {
      final qid = quote['_id']?.toString() ?? quote['id']?.toString() ?? quote['quoteId']?.toString();
      if (qid == null || qid.isEmpty) return quote;

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      // Prefer booking-scoped endpoint if we have bookingId
      final bookingId = quote['bookingId']?.toString() ?? (quote['booking'] is Map ? (quote['booking']['_id']?.toString() ?? quote['booking']['id']?.toString()) : null);
      if (bookingId != null && bookingId.isNotEmpty) {
        try {
          final listUri = Uri.parse('$API_BASE_URL/api/bookings/$bookingId/quotes/details');
          final listResp = await http.get(listUri, headers: headers).timeout(const Duration(seconds: 8));
          if (listResp.statusCode >= 200 && listResp.statusCode < 300 && listResp.body.isNotEmpty) {
            final parsed = jsonDecode(listResp.body);
            final listData = parsed is Map ? (parsed['data'] ?? parsed) : parsed;
            if (listData is List) {
              for (final item in listData) {
                if (item is Map) {
                  final id = item['_id']?.toString() ?? item['id']?.toString();
                  if (id != null && id == qid) {
                    final merged = Map<String, dynamic>.from(quote)..addAll(Map<String, dynamic>.from(item));
                    try {
                      if (kDebugMode) {
                        try {
                          debugPrint('Enriched quote (booking-scoped) qid=$qid: ${jsonEncode(merged)}');
                        } catch (_) {
                          debugPrint('Enriched quote (booking-scoped) qid=$qid: ${merged.toString()}');
                        }
                      }
                    } catch (_) {}
                    return merged;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      // Fallback: job-scoped single quote
      String? jobIdFallback;
      try {
        jobIdFallback = quote['jobId']?.toString() ?? (quote['job'] is Map ? ((quote['job']['_id'] ?? quote['job']['id'])?.toString()) : null);
      } catch (_) { jobIdFallback = null; }

      if (jobIdFallback != null && jobIdFallback.isNotEmpty) {
        try {
          final uri = Uri.parse('${API_BASE_URL.replaceAll(RegExp(r'/+\$'), '')}/api/jobs/$jobIdFallback/quotes/$qid');
          final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
          if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
            final decoded = jsonDecode(resp.body);
            final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
            if (data is Map) {
              final merged = Map<String, dynamic>.from(quote)..addAll(Map<String, dynamic>.from(data));
              try {
                if (kDebugMode) {
                  try {
                    debugPrint('Enriched quote (job-scoped) qid=$qid: ${jsonEncode(merged)}');
                  } catch (_) {
                    debugPrint('Enriched quote (job-scoped) qid=$qid: ${merged.toString()}');
                  }
                }
              } catch (_) {}
              return merged;
            }
          }
        } catch (_) {}
      }

      // If nothing improved, return original quote
      return quote;
    } catch (_) {
      return quote;
    }
  }

  String _formatBudget(dynamic budget) {
    if (budget == null) return 'Not specified';
    try {
      if (budget is num) {
        return '₦${NumberFormat('#,##0', 'en_US').format(budget)}';
      }
      final numVal = num.tryParse(budget.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (numVal != null) return '₦${NumberFormat('#,##0', 'en_US').format(numVal)}';
      return budget.toString();
    } catch (_) {
      return budget.toString();
    }
  }

  // Simple skeleton card shown while applicants data is loading.
  Widget _SkeletonCard(BuildContext context) {
    final base = Theme.of(context).cardColor;
    final highlight = Theme.of(context).dividerColor.withAlpha((0.06 * 255).round());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar skeleton
          Container(width: 52, height: 52, decoration: BoxDecoration(color: highlight, borderRadius: BorderRadius.circular(26))),
          const SizedBox(width: 12),
          // text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: double.infinity, color: highlight),
                const SizedBox(height: 8),
                Container(height: 12, width: 120, color: highlight),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: Container(height: 12, color: highlight)),
                    const SizedBox(width: 8),
                    Container(width: 70, height: 12, color: highlight),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Applicants'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchJobQuotes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show a handful of skeleton cards instead of a spinner for a
            // more pleasant loading experience.
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) => _SkeletonCard(context),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final quotes = snapshot.data ?? [];
          if (quotes.isEmpty) {
            return const Center(child: Text('No applicants yet'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: quotes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final quote = quotes[index];
              // Debug: log the raw quote details to the console for troubleshooting.
              try {
                if (kDebugMode) {
                  // Attempt JSON encoding for readable output; fall back to toString.
                  try {
                    debugPrint('Applicant quote #$index: ${jsonEncode(quote)}');
                  } catch (_) {
                    debugPrint('Applicant quote #$index: ${quote.toString()}');
                  }
                }
              } catch (_) {}
              // Resolve artisan from multiple possible fields the API might return.
              final rawArtisan = quote['artisanUser'] ?? quote['artisan'] ?? quote['user'] ?? {};
              final artisan = (rawArtisan is Map) ? Map<String, dynamic>.from(rawArtisan) : {'_id': rawArtisan?.toString() ?? ''};
              // Some endpoints return a nested artisanProfile with richer fields
              final rawProfile = quote['artisanProfile'] ?? quote['profile'] ?? artisan['profile'] ?? {};
              final artisanProfile = (rawProfile is Map) ? Map<String, dynamic>.from(rawProfile) : <String, dynamic>{};

             final name = (artisan['name'] ?? artisan['fullName'] ?? artisan['username'] ?? artisanProfile['name'] ?? 'Unknown Artisan').toString();

             // Resolve profile image URL safely; check multiple locations
              String? profileUrl;
              try {
                final img = artisan['profileImage'] ?? artisan['avatar'] ?? artisanProfile['profileImage'] ?? artisanProfile['avatar'];
                if (img is String && img.startsWith('http')) profileUrl = img;
               if (img is Map) {
                  final maybeUrl = img['url'] ?? img['secure_url'] ?? img['path'];
                 if (maybeUrl is String && maybeUrl.startsWith('http')) profileUrl = maybeUrl;
               }
             } catch (_) {}

             // Rating: prefer artisanProfile.avgRating or artisan.rating; also accept ratingCount/reviews
              double? ratingValue;
              int? ratingCount;
              try {
                ratingValue = (artisanProfile['avgRating'] ?? artisanProfile['rating'] ?? artisan['avgRating'] ?? artisan['rating'] ?? quote['rating']) is num
                    ? (artisanProfile['avgRating'] ?? artisanProfile['rating'] ?? artisan['avgRating'] ?? artisan['rating'] ?? quote['rating']) as double?
                    : (num.tryParse((artisanProfile['avgRating'] ?? artisanProfile['rating'] ?? artisan['avgRating'] ?? artisan['rating'] ?? quote['rating'])?.toString() ?? '')?.toDouble());
                ratingCount = (artisanProfile['ratingCount'] ?? artisan['ratingCount'] ?? artisanProfile['reviews'] ?? artisan['reviews'] ?? 0) is int
                    ? (artisanProfile['ratingCount'] ?? artisan['ratingCount'] ?? artisanProfile['reviews'] ?? artisan['reviews']) as int?
                   : (int.tryParse((artisanProfile['ratingCount'] ?? artisan['ratingCount'] ?? artisanProfile['reviews'] ?? artisan['reviews'])?.toString() ?? '') ?? 0);
              } catch (_) {
                ratingValue = null;
                ratingCount = 0;
              }

        // KYC detection: check various possible fields (kycVerified, kyc.status, kycLevel etc.)
              bool kycVerified = false;
              try {
                final k1 = artisan['kycVerified'] ?? artisanProfile['kycVerified'] ?? artisan['kyc'] ?? artisanProfile['kyc'];
               if (k1 is bool) kycVerified = k1;
                else if (k1 is String) kycVerified = k1.toLowerCase() == 'true' || k1.toLowerCase() == 'verified' || k1.toLowerCase() == 'approved';
                else if (k1 is Map) {
                  final s = k1['status'] ?? k1['state'] ?? k1['verified'];
                 if (s is String) kycVerified = s.toLowerCase() == 'verified' || s.toLowerCase() == 'approved';
                  if (s is bool) kycVerified = s;
                }
                // Some APIs expose kycLevel or isVerified flags
                if (!kycVerified) {
                  final lev = artisanProfile['kycLevel'] ?? artisan['kycLevel'] ?? artisan['isVerified'] ?? artisanProfile['isVerified'];
                  if (lev is bool) kycVerified = lev;
                }
              } catch (_) { kycVerified = false; }

              // Years experience and service category (from artisanProfile)
             final yearsExperience = artisanProfile['yearsExperience'] ?? artisan['yearsExperience'];
              final serviceCategory = artisanProfile['serviceCategory'] ?? artisan['serviceCategory'] ?? artisan['service'];

              // extract quote amount robustly
              dynamic quoteAmount;
              try {
                quoteAmount = quote['total'] ?? quote['amount'] ?? quote['proposedPrice'] ?? quote['price'] ?? quote['quoteAmount'];
              } catch (_) { quoteAmount = null; }

              // other useful fields to show on the card
              final status = (quote['status'] ?? quote['quoteStatus'] ?? '').toString();
              final delivery = quote['deliveryTime'] ?? quote['eta'] ?? quote['delivery'] ?? quote['leadTime'];
              final note = (quote['note'] ?? quote['message'] ?? quote['description'] ?? '').toString();
              final createdRaw = quote['createdAt'] ?? quote['created'] ?? quote['date'] ?? quote['created_at'];
               String? createdAt;
               try {
                 if (createdRaw != null) {
                   final s = createdRaw.toString();
                   final dt = DateTime.tryParse(s);
                   if (dt != null) createdAt = DateFormat.yMMMd().add_jm().format(dt);
                   else createdAt = s;
                 }
               } catch (_) { createdAt = null; }

              final subtitle = quoteAmount != null ? _formatBudget(quoteAmount) : (status.isNotEmpty ? status : '');

               // New card layout per applicant
               return Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Theme.of(context).cardColor,
                   borderRadius: BorderRadius.circular(12),
                   // Use a subtle elevation instead of a heavy outline
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withOpacity(0.04),
                       blurRadius: 10,
                       offset: const Offset(0, 3),
                     ),
                   ],
                 ),
                 child: Row(
                   crossAxisAlignment: CrossAxisAlignment.center,
                   children: [
                     // Avatar
                     CircleAvatar(
                       radius: 26,
                       backgroundColor: Theme.of(context).dividerColor.withAlpha((0.08 * 255).round()),
                       child: profileUrl != null
                           ? ClipRRect(
                               borderRadius: BorderRadius.circular(26),
                               child: Image.network(
                                 profileUrl,
                                 width: 52,
                                 height: 52,
                                 fit: BoxFit.cover,
                                 errorBuilder: (ctx, e, st) => Center(
                                   child: Text(
                                     name.isNotEmpty ? name[0].toUpperCase() : '?',
                                     style: const TextStyle(fontWeight: FontWeight.w600),
                                   ),
                                 ),
                               ),
                             )
                           : Text(
                               name.isNotEmpty ? name[0].toUpperCase() : '?',
                               style: const TextStyle(fontWeight: FontWeight.w600),
                             ),
                     ),

                     const SizedBox(width: 12),

                     // Middle content (name, rating/kyc, subtitle)
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Row(
                             crossAxisAlignment: CrossAxisAlignment.center,
                             children: [
                               Expanded(
                                 child: Text(
                                   name,
                                   style: const TextStyle(
                                     fontSize: 16,
                                     fontWeight: FontWeight.w600,
                                   ),
                                   maxLines: 1,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                               ),

                               const SizedBox(width: 8),

                               // Rating chip
                               if (ratingValue != null && (ratingValue is num ? ratingValue > 0 : ratingValue.toString().isNotEmpty))
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                   decoration: BoxDecoration(
                                     color: Theme.of(context).chipTheme.backgroundColor ?? Theme.of(context).disabledColor.withAlpha((0.06 * 255).round()),
                                     borderRadius: BorderRadius.circular(16),
                                   ),
                                   child: Row(
                                     children: [
                                       const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                       const SizedBox(width: 6),
                                       Text(
                                         '${(ratingValue ?? 0).toStringAsFixed(1)}',
                                         style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color, fontWeight: FontWeight.w600),
                                       ),
                                       if (ratingCount != null && ratingCount! > 0) ...[
                                         const SizedBox(width: 6),
                                         Text('(${ratingCount})', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                                       ]
                                     ],
                                   ),
                                 ),

                               // KYC badge
                               if (kycVerified == true)
                                 Padding(
                                   padding: const EdgeInsets.only(left: 8.0),
                                   child: Container(
                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                     decoration: BoxDecoration(
                                       color: const Color(0xFFEFFCF3),
                                       borderRadius: BorderRadius.circular(12),
                                     ),
                                     child: Row(children: [
                                       const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                                       const SizedBox(width: 6),
                                       Text('KYC verified', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                                     ]),
                                   ),
                                 ),
                             ],
                           ),

                           const SizedBox(height: 6),

                           // Amount / status line (small)
                           Text(
                             subtitle.toString(),
                             style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                           ),

                           // Show quote note/message if present
                           if ((quote['note'] ?? quote['message'] ?? quote['description'] ?? '').toString().isNotEmpty)
                                 Padding(
                               padding: const EdgeInsets.only(top: 6.0),
                               child: Text(
                                 (quote['note'] ?? quote['message'] ?? quote['description']).toString(),
                                 style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.95 * 255).round())),
                                 maxLines: 2,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),

                           // Show items if present
                           if (quote['items'] is List && (quote['items'] as List).isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(top: 6.0),
                               child: Wrap(
                                 spacing: 8,
                                 runSpacing: 6,
                                 children: (quote['items'] as List).map<Widget>((it) {
                                   String label = '';
                                   try {
                                     if (it is Map) label = (it['name'] ?? it['title'] ?? it['description'] ?? it['label'] ?? it['item'] ?? '').toString();
                                     else label = it?.toString() ?? '';
                                   } catch (_) { label = it?.toString() ?? ''; }
                                   if (label.isEmpty) return const SizedBox.shrink();
                                   return Container(
                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                     decoration: BoxDecoration(
                                       color: Theme.of(context).disabledColor.withAlpha((0.06 * 255).round()),
                                       borderRadius: BorderRadius.circular(8),
                                     ),
                                     child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                                   );
                                 }).toList(),
                               ),
                             ),
                         ],
                       ),
                     ),

                     const SizedBox(width: 12),

                     // Right: prominent quote amount, meta and view button (centered)
                     Column(
                       mainAxisSize: MainAxisSize.min,
                       mainAxisAlignment: MainAxisAlignment.center,
                       crossAxisAlignment: CrossAxisAlignment.center,
                       children: [
                         if (quoteAmount != null)
                           Text(
                             _formatBudget(quoteAmount),
                             textAlign: TextAlign.center,
                             style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: widget.primaryColor),
                           ),

                         // small meta under amount
                         if (delivery != null && delivery.toString().isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(top: 6.0),
                             child: Text(delivery.toString(), style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                           ),

                         if (status.isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(top: 4.0),
                             child: Text(status, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                           ),

                         if (createdAt != null)
                           Padding(
                             padding: const EdgeInsets.only(top: 4.0),
                             child: Text(createdAt!, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.7 * 255).round()))),
                           ),

                         const SizedBox(height: 8),

                         ElevatedButton(
                           onPressed: () {
                             try {
                               Navigator.of(context).push(MaterialPageRoute(
                                 builder: (_) => QuoteDetailsPageWidget(quote: Map<String, dynamic>.from(quote)),
                               ));
                             } catch (_) {}
                           },
                           style: ElevatedButton.styleFrom(
                             elevation: 0, // no box shadow
                             backgroundColor: widget.primaryColor,
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           ),
                           child: const Text('View', style: TextStyle(color: Colors.white)),
                         ),
                       ],
                     ),
                   ],
                 ),
               );
            },
          );
        },
      ),
    );
  }
}
