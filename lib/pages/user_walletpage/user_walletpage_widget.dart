import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../services/wallet_service.dart';
import '../../api_config.dart';
import '../../utils/error_messages.dart';

import 'user_walletpage_model.dart';
export 'user_walletpage_model.dart';

class UserWalletpageWidget extends StatefulWidget {
  const UserWalletpageWidget({super.key});

  static String routeName = 'UserWalletpage';
  static String routePath = '/userWalletpage';

  @override
  State<UserWalletpageWidget> createState() => _UserWalletpageWidgetState();
}

class _UserWalletpageWidgetState extends State<UserWalletpageWidget> {
  late UserWalletpageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loading = true;
  bool _isArtisan = false;
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _transactions = [];
  String? _error;

  // Payout details controllers
  final TextEditingController _pNameCtrl = TextEditingController();
  final TextEditingController _pAccountCtrl = TextEditingController();
  final TextEditingController _pBankCodeCtrl = TextEditingController();
  final TextEditingController _pBankNameCtrl = TextEditingController();
  final TextEditingController _pCurrencyCtrl = TextEditingController(text: 'NGN');
  bool _pSaving = false;
  final GlobalKey<FormState> _pFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UserWalletpageModel());
    _init();
  }

  @override
  void dispose() {
    _pNameCtrl.dispose();
    _pAccountCtrl.dispose();
    _pBankCodeCtrl.dispose();
    _pBankNameCtrl.dispose();
    _pCurrencyCtrl.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Prefer cached app state for role to avoid extra network calls
      final profile = AppStateNotifier.instance.profile;
      try {
        if (profile != null) {
          final r = (profile['role'] ?? profile['type'] ?? '').toString().toLowerCase();
          _isArtisan = r.contains('artisan');
        } else {
          final role = await UserService.getRole();
          _isArtisan = role == 'artisan';
        }
      } catch (_) {
        final role = await UserService.getRole();
        _isArtisan = role == 'artisan';
      }

      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'Not authenticated';
          _loading = false;
        });
        return;
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      };

      // Fetch wallet summary
      try {
        final uri = Uri.parse('$API_BASE_URL/api/wallet');
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map) {
            _wallet = Map<String, dynamic>.from(data);
          }
        }
      } catch (e) {
        // Non-fatal error
      }

      // Fetch recent transactions using WalletService
      try {
        final token = await TokenStorage.getToken();
        if (token != null && token.isNotEmpty) {
          final fetched = await WalletService.fetchTransactions(token: token);
          // Filter to only transactions that belong to the current user
          final prof = AppStateNotifier.instance.profile;
          final myId = (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])?.toString();
          if (myId != null && myId.isNotEmpty) {
            _transactions = fetched.where((tx) => _transactionBelongsToUser(tx, myId)).toList();
          } else {
            _transactions = fetched;
          }
        }
      } catch (e) {
        // Surface a subtle error message for transactions and allow retry
        if (kDebugMode) debugPrint('Failed to fetch transactions: $e');
        _error = 'Unable to load transactions';
      }
    } catch (e) {
      _error = ErrorMessages.humanize(e);
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _savePayoutDetails() async {
    setState(() { _pSaving = true; });

    try {
      final token = await TokenStorage.getToken();
      if (token == null) throw Exception('Not authenticated');

      // Use PUT to update/replace payout details (API docs expose GET for this path
      // and servers commonly use PUT for updates). Send JSON with the exact keys
      // the API returns: name, account_number, bank_code, bank_name, currency.
      final uri = Uri.parse('$API_BASE_URL/api/wallet/payout-details');
      final bodyMap = {
        'name': _pNameCtrl.text.trim(),
        'account_number': _pAccountCtrl.text.trim(),
        'bank_name': _pBankNameCtrl.text.trim(),
        'bank_code': _pBankCodeCtrl.text.trim(),
        'currency': _pCurrencyCtrl.text.trim().isEmpty ? 'NGN' : _pCurrencyCtrl.text.trim(),
      };

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Try PUT first, but some servers may expect POST — fallback on 404.
      http.Response resp = await http
          .put(uri, body: jsonEncode(bodyMap), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 404) {
        if (kDebugMode) debugPrint('PUT returned 404, retrying with POST');
        resp = await http
            .post(uri, body: jsonEncode(bodyMap), headers: headers)
            .timeout(const Duration(seconds: 12));
      }

      // If both JSON PUT/POST failed (non-2xx), some servers expect multipart/form-data.
      if (!(resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty)) {
        if (kDebugMode) debugPrint('JSON save failed (${resp.statusCode}), trying multipart/form-data fallback');
        final mpReq = http.MultipartRequest('POST', uri);
        mpReq.headers.addAll({ 'Authorization': 'Bearer $token' });
        mpReq.fields['name'] = bodyMap['name'] ?? '';
        mpReq.fields['account_number'] = bodyMap['account_number'] ?? '';
        mpReq.fields['bank_name'] = bodyMap['bank_name'] ?? '';
        mpReq.fields['bank_code'] = bodyMap['bank_code'] ?? '';
        mpReq.fields['currency'] = bodyMap['currency'] ?? 'NGN';
        final streamed = await mpReq.send().timeout(const Duration(seconds: 15));
        final mpResp = await http.Response.fromStream(streamed);
        resp = mpResp;
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        // Parse response and update wallet state when server returns updated object
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        if (data is Map) {
          setState(() { _wallet = Map<String, dynamic>.from(data); });
        }
        if (mounted) Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account details saved'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        // Log response for debugging when server replies with 4xx/5xx
        if (kDebugMode) debugPrint('Save payout response: ${resp.statusCode} ${resp.body}');
        String msg;
        try {
          if (resp.body.isNotEmpty) {
            final parsed = jsonDecode(resp.body);
            if (parsed is Map && (parsed['message'] ?? parsed['error']) != null) {
              msg = (parsed['message'] ?? parsed['error']).toString();
            } else {
              msg = 'Failed to save account details';
            }
          } else {
            msg = 'Failed to save account details (status ${resp.statusCode})';
          }
        } catch (_) {
          msg = 'Failed to save account details (status ${resp.statusCode})';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
       }
     } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.humanize(e)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
     } finally {
       if (mounted) setState(() { _pSaving = false; });
     }
   }

   Future<void> _showPayoutDetailsSheet({bool isEdit = false}) async {
     // Fetch latest payout details
     try {
       final token = await TokenStorage.getToken();
       if (token != null && token.isNotEmpty) {
         final uri = Uri.parse('$API_BASE_URL/api/wallet/payout-details');
         final resp = await http.get(
             uri,
             headers: {
               'Content-Type': 'application/json',
               'Authorization': 'Bearer $token'
             }
         ).timeout(const Duration(seconds: 10));

         if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
           try {
             final decoded = jsonDecode(resp.body);
             final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
             if (data is Map) {
               setState(() {
                 _wallet ??= {};
                 _wallet!['payoutDetails'] = Map<String, dynamic>.from(data);
               });
             }
           } catch (_) {}
         }
       }
     } catch (_) {}

    // Prefill controllers
    final pd = _wallet?['payoutDetails'] is Map
        ? Map<String, dynamic>.from(_wallet!['payoutDetails'])
        : null;

    _pNameCtrl.text = pd?['name']?.toString() ?? '';
    _pAccountCtrl.text = pd?['account_number']?.toString() ?? '';
    _pBankCodeCtrl.text = pd?['bank_code']?.toString() ?? '';
    _pBankNameCtrl.text = pd?['bank_name']?.toString() ?? '';
    _pCurrencyCtrl.text = pd?['currency']?.toString() ?? 'NGN';

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                      24,
                      16,
                      24,
                      MediaQuery.of(context).viewInsets.bottom + 24
                  ),
                  child: ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withAlpha((0.3 * 255).round()),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isEdit ? 'Edit Account Details' : 'Account Details',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: _pFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account Information',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _pNameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Account holder name',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pAccountCtrl,
                              decoration: InputDecoration(
                                labelText: 'Account number',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final s = v.trim();
                                if (!RegExp(r'^\d{10}$').hasMatch(s)) {
                                  return 'Enter a 10-digit account number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            // Bank code (required by some payout providers like Paystack)
                            TextFormField(
                              controller: _pBankCodeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Bank code',
                                hintText: 'e.g. 058',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pBankNameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Bank name',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pCurrencyCtrl,
                              decoration: InputDecoration(
                                labelText: 'Currency',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _pSaving ? null : () async {
                                  if (!_pFormKey.currentState!.validate()) return;
                                  await _savePayoutDetails();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: _pSaving
                                    ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                )
                                    : Text('Save Account Details'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
          );
        }
     );
   }

  // Simple pagination: attempt to load more using page & limit query params where supported
  int _txPage = 1;
  final int _txLimit = 25;
  bool _txLoadingMore = false;
  bool _txHasMore = true;

  Future<void> _loadMoreTransactions() async {
    if (_txLoadingMore || !_txHasMore) return;
    setState(() => _txLoadingMore = true);
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) return;
      _txPage += 1;
      // Try to call the first endpoint with page/limit, fallback to fetchTransactions
      final base = API_BASE_URL;
      final uri = Uri.parse('$base/api/transactions?page=$_txPage&limit=$_txLimit');
      try {
        final resp = await http.get(uri, headers: { 'Content-Type':'application/json', 'Authorization': 'Bearer $token' }).timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final list = decoded is Map ? (decoded['data'] ?? decoded['transactions'] ?? decoded['results'] ?? decoded) : decoded;
          if (list is List && list.isNotEmpty) {
            final additional = List<Map<String, dynamic>>.from(list.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'raw': e}));
            final prof = AppStateNotifier.instance.profile;
            final myId = (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])?.toString();
            if (myId != null && myId.isNotEmpty) {
              _transactions.addAll(additional.where((tx) => _transactionBelongsToUser(tx, myId)));
            } else {
              _transactions.addAll(additional);
            }
            if (additional.length < _txLimit) _txHasMore = false;
            return;
          } else {
            _txHasMore = false;
          }
        }
      } catch (_) {
        // fallback to WalletService; but we can't easily merge incremental results, so just stop
        _txHasMore = false;
      }
    } catch (_) {}
    finally { setState(() => _txLoadingMore = false); }
  }

  String _formatAmount(dynamic value) {
    try {
      if (value == null) return '0';

      // Normalize to a number
      double number;
      if (value is String) {
        number = double.tryParse(value) ?? 0.0;
      } else if (value is int) {
        number = value.toDouble();
      } else if (value is double) {
        number = value;
      } else {
        number = 0.0;
      }

      // Determine currency code from wallet if available
      final walletCurrency = _wallet == null
          ? null
          : (_wallet!['currency'] ?? _wallet!['currencyCode'] ?? _wallet!['currency_code']);
      final currencyCode = (walletCurrency is String && walletCurrency.isNotEmpty) ? walletCurrency.toUpperCase() : 'NGN';

      try {
        // Use simpleCurrency so symbol is localized where possible
        final formatter = NumberFormat.simpleCurrency(name: currencyCode);
        // Format without decimals for whole currency units
        return formatter.format(number.round());
      } catch (_) {
        // Fallback: use grouping and a simple symbol map
        final formatter = NumberFormat.decimalPattern();
        final symbolMap = <String, String>{'NGN': '₦', 'USD': '\$', 'EUR': '€', 'GBP': '£'};
        final sym = symbolMap[currencyCode] ?? '';
        return '${sym}${formatter.format(number.round())}';
      }
    } catch (e) {
      return value.toString();
    }
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final theme = Theme.of(context);
    final ff = FlutterFlowTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final type = (transaction['type'] ?? '').toString().toLowerCase();
    final status = (transaction['status'] ?? '').toString().toLowerCase();
    final isCredit = type == 'credit';
    final isPending = status.contains('pending');

    final title = transaction['title']?.toString() ??
        (isCredit ? 'Payout' : 'Payment');
    final description = transaction['subtitle']?.toString() ??
        (transaction['description']?.toString() ??
            (isCredit ? 'Wallet credit' : 'Wallet debit'));
    final amount = transaction['amount'] ?? transaction['value'] ?? 0;
    final date = transaction['date']?.toString() ??
        transaction['createdAt']?.toString() ??
        'Just now';

    Color statusColor;
    if (isPending) {
      statusColor = ff.warning;
    } else if (isCredit) {
      statusColor = ff.success;
    } else {
      statusColor = theme.colorScheme.error;
    }

    IconData icon;
    if (isCredit) {
      icon = Icons.arrow_downward_rounded;
    } else {
      icon = Icons.arrow_upward_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: statusColor,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              date,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha((0.4 * 255).round()),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isCredit ? '+' : '-'}${_formatAmount(amount)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isPending ? 'Pending' : (isCredit ? 'Completed' : 'Debited'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to determine if a transaction belongs to the logged-in user
  bool _transactionBelongsToUser(Map<String, dynamic> tx, String? myId) {
    // If we don't have a logged-in user's id, be conservative and treat
    // transactions as not belonging to the current user. Returning `true` here
    // may show other users' transactions in multi-tenant responses.
    if (myId == null || myId.isEmpty) return false;

    final candidateKeys = [
      'userId', 'user_id', 'user', 'customerId', 'customer_id', 'recipientId', 'recipient',
      'clientId', 'artisanId', 'ownerId', 'from', 'to', 'account', 'accountId', 'walletId', 'customer', 'owner', 'createdBy'
    ];

    for (final k in candidateKeys) {
      if (!tx.containsKey(k)) continue;
      final v = tx[k];
      if (v == null) continue;
      if (v is String || v is num) {
        if (v.toString() == myId) return true;
      } else if (v is Map) {
        final nested = (v['_id'] ?? v['id'] ?? v['userId'] ?? v['customerId']);
        if (nested != null && nested.toString() == myId) return true;
      }
    }

    // Fallback: check top-level values for exact id match (less strict)
    try {
      for (final val in tx.values) {
        if (val == null) continue;
        if (val is String || val is num) {
          if (val.toString() == myId) return true;
        }
      }
    } catch (_) {}

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_error != null) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading wallet',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _init,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back arrow (use same chevron style as Notification page)
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: colorScheme.onSurface.withAlpha((0.8 * 255).round()),
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Text(
                    'Wallet',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  // Refresh action
                  IconButton(
                    onPressed: _handleRefreshPressed,
                    icon: _txLoadingMore
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(colorScheme.onSurface),
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: colorScheme.onSurface,
                            size: 22,
                          ),
                  ),
                ],
              ),
            ),

            // Wallet Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _init,
                color: colorScheme.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24.0,
                      0.0,
                      24.0,
                      MediaQuery.of(context).padding.bottom + 80.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // Balance Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Balance',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                                      ),
                                    ),
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withAlpha((0.1 * 255).round()),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: colorScheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _loading
                                    ? Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                )
                                    : Text(
                                  _formatAmount(
                                      _wallet?['total'] ??
                                          _wallet?['balance'] ??
                                          _wallet?['totalEarned'] ??
                                          _wallet?['totalSpent'] ?? 0
                                  ),
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 32,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Available',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _loading
                                              ? Container(
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          )
                                              : Text(
                                            _formatAmount(
                                                _wallet?['available'] ??
                                                    _wallet?['availableBalance'] ??
                                                    _wallet?['balance'] ?? 0
                                            ),
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pending',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _loading
                                              ? Container(
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          )
                                              : Text(
                                            _formatAmount(
                                                _wallet?['pending'] ??
                                                    _wallet?['pendingAmount'] ?? 0
                                            ),
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Payout Account Section (for artisans)
                        if (_isArtisan) ...[
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                            child: Text(
                              'PAYOUT ACCOUNT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Payout Details',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _showPayoutDetailsSheet(isEdit: true),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                        ),
                                        child: Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (_wallet != null && _wallet!['payoutDetails'] != null) ...[
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Account Name',
                                      value: _wallet!['payoutDetails']['name']?.toString() ?? '—',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Account Number',
                                      value: _wallet!['payoutDetails']['account_number']?.toString() ?? '—',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Bank',
                                      value: _wallet!['payoutDetails']['bank_name']?.toString() ?? '—',
                                    ),
                                  ] else ...[
                                    Text(
                                      'No payout details set',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () => _showPayoutDetailsSheet(isEdit: false),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        minimumSize: const Size(double.infinity, 0),
                                      ),
                                      child: Text('Add Account Details'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Recent Transactions Section
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                          child: Text(
                            'RECENT TRANSACTIONS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        if (_loading && _transactions.isEmpty)
                          ...List.generate(3, (index) => _buildTransactionSkeleton(context)),
                        if (!_loading && _transactions.isEmpty && _error == null)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 48,
                                    color: colorScheme.onSurface.withAlpha((0.3 * 255).round()),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No transactions yet',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!_loading && _transactions.isNotEmpty)
                          ..._transactions.map(_buildTransactionItem).toList(),

                        // Transaction errors section
                        if (!_loading && _error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Column(
                              children: [
                                Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                                const SizedBox(height: 8),
                                ElevatedButton(onPressed: _init, child: const Text('Retry')),
                              ],
                            ),
                          ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        title: Container(
          height: 16,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              height: 12,
              width: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              height: 16,
              width: 60,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 20,
              width: 70,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Refresh button behavior: if more transactions are available, load next page;
  // otherwise perform a full refresh (_init()). This replaces the in-body "Load more" button.
  Future<void> _handleRefreshPressed() async {
    if (_txHasMore && !_txLoadingMore && !_loading) {
      await _loadMoreTransactions();
      return;
    }

    // Otherwise perform a full refresh
    await _init();
  }
}


