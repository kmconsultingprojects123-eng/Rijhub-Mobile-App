import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/token_storage.dart';
import '../../services/user_service.dart';
import '../../services/wallet_service.dart';
import '../../services/notification_controller.dart';
import '../../services/notification_service.dart';
import '../../api_config.dart';
import '../../utils/error_messages.dart';
import 'dart:async';

import 'user_walletpage_model.dart';
export 'user_walletpage_model.dart';

// kDebugMode fallback: some analyzer environments may not resolve Flutter packages.
// If the real `kDebugMode` from Flutter is available, it will be used; otherwise
// this local const will provide a safe default (false in production builds).
const bool kDebugMode = bool.fromEnvironment('dart.vm.product') == false;

// ------------------------------------------------------------
// Structured API logging (request/response/error)
// ------------------------------------------------------------
bool get _apiLogsEnabled => kDebugMode;

int _apiLogSeq = 0;

String _newApiLogId(String prefix) {
  _apiLogSeq += 1;
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$_apiLogSeq';
}

String _truncateForLog(String value, {int maxChars = 4000}) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}… (truncated, ${value.length} chars total)';
}

Map<String, String> _redactHeadersForLog(Map<String, String>? headers) {
  final out = <String, String>{};
  if (headers == null) return out;
  headers.forEach((k, v) {
    final key = k.toLowerCase();
    if (key == 'authorization') {
      if (v.toLowerCase().startsWith('bearer ')) {
        out[k] = 'Bearer ***';
      } else {
        out[k] = '***';
      }
      return;
    }
    if (key == 'cookie' || key == 'set-cookie') {
      out[k] = '***';
      return;
    }
    out[k] = v;
  });
  return out;
}

Object? _loggableBody(Object? body) {
  if (body == null) return null;
  if (body is Map || body is List) return body;
  if (body is String) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    // Try JSON decode to make logs easier to scan.
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        // Fall back to string.
      }
    }
    return _truncateForLog(trimmed);
  }
  return body.toString();
}

void _apiLog(String requestId, String phase, Map<String, Object?> data) {
  if (!_apiLogsEnabled) return;
  final safe = <String, Object?>{
    'ts': DateTime.now().toIso8601String(),
    ...data,
  };
  final pretty = const JsonEncoder.withIndent('  ').convert(safe);
  debugPrint('========== API [$requestId] $phase ==========');
  // debugPrint truncates long strings; chunk to keep full payload.
  const chunkSize = 800;
  for (var i = 0; i < pretty.length; i += chunkSize) {
    final end =
        (i + chunkSize < pretty.length) ? (i + chunkSize) : pretty.length;
    debugPrint(pretty.substring(i, end));
  }
  debugPrint('========== END API [$requestId] $phase ==========');
}

Future<http.Response> _loggedHttpCall({
  required String requestId,
  required String label,
  required String method,
  required Uri uri,
  Map<String, String>? headers,
  Object? body,
  Duration? timeout,
  required Future<http.Response> Function() send,
}) async {
  final sw = Stopwatch()..start();
  _apiLog(requestId, 'REQUEST', {
    'label': label,
    'method': method,
    'url': uri.toString(),
    'timeoutMs': timeout?.inMilliseconds,
    'headers': _redactHeadersForLog(headers),
    'body': _loggableBody(body),
  });
  try {
    final f = send();
    final resp = timeout == null ? await f : await f.timeout(timeout);
    sw.stop();
    _apiLog(requestId, 'RESPONSE', {
      'label': label,
      'method': method,
      'url': uri.toString(),
      'elapsedMs': sw.elapsedMilliseconds,
      'statusCode': resp.statusCode,
      'headers': _redactHeadersForLog(resp.headers),
      'body': _loggableBody(resp.body),
    });
    return resp;
  } catch (e, st) {
    sw.stop();
    _apiLog(requestId, 'ERROR', {
      'label': label,
      'method': method,
      'url': uri.toString(),
      'elapsedMs': sw.elapsedMilliseconds,
      'error': e.toString(),
      'stack': _truncateForLog(st.toString(), maxChars: 6000),
    });
    rethrow;
  }
}

Future<http.Response> _sendLoggedMultipartRequest({
  required String requestId,
  required String label,
  required http.MultipartRequest request,
  Duration? timeout,
}) async {
  final sw = Stopwatch()..start();
  _apiLog(requestId, 'REQUEST', {
    'label': label,
    'method': request.method,
    'url': request.url.toString(),
    'timeoutMs': timeout?.inMilliseconds,
    'headers': _redactHeadersForLog(request.headers),
    'fields': request.fields,
    'files': request.files
        .map((f) => {
              'field': f.field,
              'filename': f.filename,
              'length': f.length,
              'contentType': f.contentType.toString(),
            })
        .toList(),
  });
  try {
    final streamedFuture = request.send();
    final streamed = timeout == null
        ? await streamedFuture
        : await streamedFuture.timeout(timeout);
    final resp = await http.Response.fromStream(streamed);
    sw.stop();
    _apiLog(requestId, 'RESPONSE', {
      'label': label,
      'method': request.method,
      'url': request.url.toString(),
      'elapsedMs': sw.elapsedMilliseconds,
      'statusCode': resp.statusCode,
      'headers': _redactHeadersForLog(resp.headers),
      'body': _loggableBody(resp.body),
    });
    return resp;
  } catch (e, st) {
    sw.stop();
    _apiLog(requestId, 'ERROR', {
      'label': label,
      'method': request.method,
      'url': request.url.toString(),
      'elapsedMs': sw.elapsedMilliseconds,
      'error': e.toString(),
      'stack': _truncateForLog(st.toString(), maxChars: 6000),
    });
    rethrow;
  }
}

/// Bank picker sheet content that manages its own loading state so it rebuilds
/// when the API completes (modal routes don't rebuild when parent setState runs).
class _BankPickerSheetContent extends StatefulWidget {
  const _BankPickerSheetContent({
    required this.selectedBankCode,
    required this.onBankSelected,
    this.scrollController,
  });

  final String? selectedBankCode;
  final Future<void> Function(String code, String name) onBankSelected;
  final ScrollController? scrollController;

  @override
  State<_BankPickerSheetContent> createState() =>
      _BankPickerSheetContentState();
}

class _BankPickerSheetContentState extends State<_BankPickerSheetContent> {
  bool _loading = true;
  List<Map<String, String>> _banks = [];
  String _query = '';

  Future<void> _loadBanks() async {
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final banksUri = Uri.parse('$API_BASE_URL/api/payments/banks');
      final reqId = _newApiLogId('banks');
      final bResp = await _loggedHttpCall(
        requestId: '$reqId.get',
        label: 'bankPicker.loadBanks',
        method: 'GET',
        uri: banksUri,
        headers: headers,
        timeout: const Duration(seconds: 8),
        send: () => http.get(banksUri, headers: headers),
      );
      if (bResp.statusCode >= 200 &&
          bResp.statusCode < 300 &&
          bResp.body.isNotEmpty) {
        final bDecoded = jsonDecode(bResp.body);
        final list = bDecoded is Map
            ? (bDecoded['data'] ?? bDecoded['banks'] ?? bDecoded)
            : bDecoded;
        if (list is List) {
          final parsed = list
              .map<Map<String, String>>((e) {
                if (e is Map) {
                  final name =
                      (e['name'] ?? e['bank_name'] ?? e['bank'])?.toString() ??
                          '';
                  final code =
                      (e['code'] ?? e['bank_code'] ?? e['id'])?.toString() ??
                          '';
                  return <String, String>{'name': name, 'code': code};
                }
                return <String, String>{'name': e.toString(), 'code': ''};
              })
              .where((m) => (m['code'] ?? '').isNotEmpty)
              .toList();
          if (parsed.isNotEmpty && mounted) {
            setState(() {
              _banks = parsed;
              _loading = false;
            });
            return;
          }
        }
      }
      if (kDebugMode) debugPrint('Banks fetch returned ${bResp.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to fetch banks: $e');
    }
    if (mounted) {
      setState(() {
        _banks = [
          {'name': 'GTBank', 'code': '058'},
          {'name': 'First Bank', 'code': '011'},
          {'name': 'Zenith Bank', 'code': '057'},
          {'name': 'Access Bank', 'code': '044'},
          {'name': 'UBA', 'code': '033'},
        ];
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setInner) {
        final filtered = _banks
            .where((b) =>
                (b['name'] ?? '').toLowerCase().contains(_query.toLowerCase()))
            .toList();

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search bank',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                ),
                onChanged: (v) => setInner(() => _query = v),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Loading banks...',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha((0.6 * 255).round()),
                              ),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No banks match "$_query"',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withAlpha((0.6 * 255).round()),
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: widget.scrollController,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 0),
                            itemBuilder: (ctx2, i) {
                              final b = filtered[i];
                              final code = b['code'] ?? '';
                              final name = b['name'] ?? code;
                              final selected = widget.selectedBankCode == code;
                              return ListTile(
                                title: Text(name),
                                subtitle: code.isNotEmpty ? Text(code) : null,
                                trailing: selected
                                    ? Icon(Icons.check,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)
                                    : null,
                                onTap: () async {
                                  await widget.onBankSelected(code, name);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              );
                            },
                          ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

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
  // Whether to hide the total balance on screen (eye toggle)
  bool _hideBalance = false;
  // Track last-known transaction statuses to detect transitions (id -> status)
  final Map<String, String> _txStatusMap = {};
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _transactions = [];
  String? _error;

  // Payout details controllers
  final TextEditingController _pNameCtrl = TextEditingController();
  final TextEditingController _pAccountCtrl = TextEditingController();
  final TextEditingController _pBankNameCtrl = TextEditingController();
  // account name controller populated by server lookup
  final TextEditingController _pAccountNameCtrl = TextEditingController();
  final TextEditingController _pCurrencyCtrl =
      TextEditingController(text: 'NGN');
  final TextEditingController _pBankCodeCtrl = TextEditingController();
  bool _pSaving = false;
  bool _pEditLoading = false;
  final GlobalKey<FormState> _pFormKey = GlobalKey<FormState>();
  // bank list and selection state
  List<Map<String, String>> _bankList = [];
  String? _selectedBankCode;
  bool _isAccountNameLoading = false;
  Timer? _resolveTimer;

  /// Save button is enabled only when: bank selected, account number entered,
  /// account name resolved successfully, and not currently saving/loading.
  bool get _canSavePayoutDetails =>
      !_pSaving &&
      !_isAccountNameLoading &&
      (_selectedBankCode != null && _selectedBankCode!.isNotEmpty) &&
      _pAccountCtrl.text.trim().length >= 6 &&
      _pAccountNameCtrl.text.trim().isNotEmpty;

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
    _pBankNameCtrl.dispose();
    _pAccountNameCtrl.dispose();
    _pCurrencyCtrl.dispose();
    _pBankCodeCtrl.dispose();
    _resolveTimer?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _toggleBalanceVisibility() {
    if (!mounted) return;
    setState(() {
      _hideBalance = !_hideBalance;
    });
  }

  Future<void> _init() async {
    if (kDebugMode) debugPrint('[UserWalletpage] _init called');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Prefer cached app state for role to avoid extra network calls
      final profile = AppStateNotifier.instance.profile;
      try {
        if (profile != null) {
          final r = (profile['role'] ?? profile['type'] ?? '')
              .toString()
              .toLowerCase();
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
        if (kDebugMode)
          debugPrint('[UserWalletpage] Fetching wallet summary from: $uri');
        final reqId = _newApiLogId('wallet');
        final resp = await _loggedHttpCall(
          requestId: '$reqId.get',
          label: 'wallet.init.fetchSummary',
          method: 'GET',
          uri: uri,
          headers: headers,
          timeout: const Duration(seconds: 12),
          send: () => http.get(uri, headers: headers),
        );
        if (kDebugMode)
          debugPrint(
              '[UserWalletpage] Wallet summary response: ${resp.statusCode} ${resp.body}');

        if (resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
          if (data is Map) {
            _wallet = Map<String, dynamic>.from(data);
          }
        }
      } catch (e) {
        // Non-fatal error
      }

      // Fetch recent transactions using WalletService and detect status transitions
      try {
        final token = await TokenStorage.getToken();
        if (token != null && token.isNotEmpty) {
          final fetched = await WalletService.fetchTransactions(token: token);
          // Filter to only transactions that belong to the current user
          final prof = AppStateNotifier.instance.profile;
          final myId =
              (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])?.toString();
          List<Map<String, dynamic>> rawList;
          if (myId != null && myId.isNotEmpty) {
            rawList = fetched
                .where((tx) => _transactionBelongsToUser(tx, myId))
                .toList();
          } else {
            rawList = fetched;
          }

          // Compare previous statuses to detect transitions (e.g., pending -> completed)
          for (final tx in rawList) {
            final id = _txId(tx);
            final status =
                (tx['status'] ?? tx['transactionStatus'] ?? tx['state'] ?? '')
                    .toString()
                    .toLowerCase();
            final prev = _txStatusMap[id];
            if (id.isNotEmpty) {
              // If previously pending/processing and now not pending -> consider completed
              final wasPending = prev != null &&
                  (prev.contains('pending') ||
                      prev.contains('processing') ||
                      prev.contains('holding'));
              final nowPending = status.contains('pending') ||
                  status.contains('processing') ||
                  status.contains('holding');
              if (wasPending && !nowPending) {
                // New completion observed — notify locally and ask server to create a notification
                try {
                  final title = 'Payout completed';
                  final amount =
                      tx['amount'] ?? tx['value'] ?? tx['total'] ?? '';
                  final body = amount != null && amount.toString().isNotEmpty
                      ? 'A payout of ${_formatAmount(amount)} is completed.'
                      : 'Your payout has been completed.';
                  // Local notification
                  await NotificationController.showLocalNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: title,
                    body: body,
                    payload: {'type': 'payout', 'txId': id},
                  );
                  // Server-side record (best-effort)
                  final prof = AppStateNotifier.instance.profile;
                  final myId2 = (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])
                      ?.toString();
                  if (myId2 != null && myId2.isNotEmpty) {
                    await NotificationService.sendNotification(
                        myId2, title, body,
                        payload: {'type': 'payout', 'txId': id});
                  }
                } catch (_) {}
              }
              // update map
              if (id.isNotEmpty) _txStatusMap[id] = status;
            }
          }

          _transactions = rawList;
        }
      } catch (e) {
        // Surface a subtle error message for transactions and allow retry
        if (kDebugMode) debugPrint('Failed to fetch transactions: $e');
        _error = 'Unable to load transactions';
      }
    } catch (e) {
      _error = ErrorMessages.humanize(e);
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _savePayoutDetails() async {
    if (kDebugMode) debugPrint('[UserWalletpage] _savePayoutDetails called');
    setState(() {
      _pSaving = true;
    });

    try {
      final token = await TokenStorage.getToken();
      if (token == null) throw Exception('Not authenticated');

      // Use PUT to update/replace payout details (API docs expose GET for this path
      // and servers commonly use PUT for updates). Send JSON with the exact keys
      // the API returns: name, account_number, bank_code, bank_name, currency.
      final uri = Uri.parse('$API_BASE_URL/api/wallet/payout-details');
      final bodyMap = {
        // Use the auto-resolved account name when available, otherwise fallback to any manual name field
        'name': (_pAccountNameCtrl.text.trim().isNotEmpty
            ? _pAccountNameCtrl.text.trim()
            : _pNameCtrl.text.trim()),
        'account_number': _pAccountCtrl.text.trim(),
        'bank_code': _pBankCodeCtrl.text.trim(),
        'bank_name': _pBankNameCtrl.text.trim(),
        'currency': _pCurrencyCtrl.text.trim().isEmpty
            ? 'NGN'
            : _pCurrencyCtrl.text.trim(),
      };
      if (kDebugMode)
        debugPrint(
            '[UserWalletpage] Saving payout details to: $uri Payload: $bodyMap');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Try PUT first, but some servers may expect POST — fallback on 404.
      final reqGroupId = _newApiLogId('payoutDetails');
      http.Response resp = await _loggedHttpCall(
        requestId: '$reqGroupId.put',
        label: 'wallet.savePayoutDetails',
        method: 'PUT',
        uri: uri,
        headers: headers,
        body: bodyMap,
        timeout: const Duration(seconds: 12),
        send: () => http.put(uri, body: jsonEncode(bodyMap), headers: headers),
      );
      if (kDebugMode)
        debugPrint(
            '[UserWalletpage] PUT response: ${resp.statusCode} ${resp.body}');

      if (resp.statusCode == 404) {
        if (kDebugMode) debugPrint('PUT returned 404, retrying with POST');
        resp = await _loggedHttpCall(
          requestId: '$reqGroupId.postFallback',
          label: 'wallet.savePayoutDetails',
          method: 'POST',
          uri: uri,
          headers: headers,
          body: bodyMap,
          timeout: const Duration(seconds: 12),
          send: () =>
              http.post(uri, body: jsonEncode(bodyMap), headers: headers),
        );
        if (kDebugMode)
          debugPrint(
              '[UserWalletpage] POST fallback response: ${resp.statusCode} ${resp.body}');
      }

      // If both JSON PUT/POST failed (non-2xx), some servers expect multipart/form-data.
      if (!(resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty)) {
        if (kDebugMode)
          debugPrint(
              'JSON save failed (${resp.statusCode}), trying multipart/form-data fallback');
        final mpReq = http.MultipartRequest('POST', uri);
        mpReq.headers.addAll({'Authorization': 'Bearer $token'});
        mpReq.fields['name'] = bodyMap['name'] ?? '';
        mpReq.fields['account_number'] = bodyMap['account_number'] ?? '';
        mpReq.fields['bank_code'] = bodyMap['bank_code'] ?? '';
        mpReq.fields['bank_name'] = bodyMap['bank_name'] ?? '';
        mpReq.fields['currency'] = bodyMap['currency'] ?? 'NGN';
        resp = await _sendLoggedMultipartRequest(
          requestId: '$reqGroupId.multipartFallback',
          label: 'wallet.savePayoutDetails.multipartFallback',
          request: mpReq,
          timeout: const Duration(seconds: 15),
        );
        if (kDebugMode)
          debugPrint(
              '[UserWalletpage] Multipart fallback response: ${resp.statusCode} ${resp.body}');
      }

      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        // Parse response and update wallet state when server returns updated object
        final decoded = jsonDecode(resp.body);
        final data = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        if (data is Map) {
          setState(() {
            _wallet = Map<String, dynamic>.from(data);
          });
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
        // Inform backend to create a notification record (best-effort)
        try {
          final prof = AppStateNotifier.instance.profile;
          final myId =
              (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])?.toString();
          if (myId != null && myId.isNotEmpty) {
            await NotificationService.sendNotification(
              myId,
              'Payout details updated',
              'Your payout account details were updated successfully.',
              payload: {'type': 'payout_update'},
            );
          }
        } catch (_) {}
      } else {
        // Log response for debugging when server replies with 4xx/5xx
        if (kDebugMode)
          debugPrint('Save payout response: ${resp.statusCode} ${resp.body}');
        String msg;
        try {
          if (resp.body.isNotEmpty) {
            final parsed = jsonDecode(resp.body);
            if (parsed is Map &&
                (parsed['message'] ?? parsed['error']) != null) {
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

        if (mounted) _showErrorDialog(msg);
      }
    } catch (e) {
      if (mounted) _showErrorDialog(ErrorMessages.humanize(e));
    } finally {
      if (mounted)
        setState(() {
          _pSaving = false;
        });
    }
  }

  void _showErrorDialog(String message) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Unable to Save',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'OK',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPayoutDetailsSheet({bool isEdit = false}) async {
    // Fetch latest payout details
    try {
      final token = await TokenStorage.getToken();
      if (token != null && token.isNotEmpty) {
        final reqGroupId = _newApiLogId('payoutSheet');
        final uri = Uri.parse('$API_BASE_URL/api/wallet/payout-details');
        final resp = await _loggedHttpCall(
          requestId: '$reqGroupId.getPayoutDetails',
          label: 'wallet.payoutSheet.fetchPayoutDetails',
          method: 'GET',
          uri: uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          timeout: const Duration(seconds: 10),
          send: () => http.get(uri, headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          }),
        );

        if (resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(resp.body);
            // prefer payoutDetails key, then data, then raw
            final pd = decoded is Map
                ? (decoded['payoutDetails'] ?? decoded['data'] ?? decoded)
                : decoded;
            if (pd is Map) {
              setState(() {
                _wallet ??= {};
                _wallet!['payoutDetails'] = Map<String, dynamic>.from(pd);
              });
            }
          } catch (_) {}
        }
        // Fetch bank list from server (per API_DOCS: GET /payment/banks)
        try {
          final banksUri = Uri.parse('$API_BASE_URL/api/payments/banks');
          final bResp = await _loggedHttpCall(
            requestId: '$reqGroupId.getBanks',
            label: 'wallet.payoutSheet.fetchBanks',
            method: 'GET',
            uri: banksUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            timeout: const Duration(seconds: 8),
            send: () => http.get(banksUri, headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            }),
          );
          if (bResp.statusCode >= 200 &&
              bResp.statusCode < 300 &&
              bResp.body.isNotEmpty) {
            final bDecoded = jsonDecode(bResp.body);
            // docs: banks list items: { name, slug, code, longcode, ... }
            final list = bDecoded is Map
                ? (bDecoded['data'] ?? bDecoded['banks'] ?? bDecoded)
                : bDecoded;
            if (list is List) {
              final parsed = list
                  .map<Map<String, String>>((e) {
                    if (e is Map) {
                      final name = (e['name'] ?? e['bank_name'] ?? e['bank'])
                              ?.toString() ??
                          '';
                      final code = (e['code'] ?? e['bank_code'] ?? e['id'])
                              ?.toString() ??
                          '';
                      return <String, String>{'name': name, 'code': code};
                    }
                    return <String, String>{'name': e.toString(), 'code': ''};
                  })
                  .where((m) => (m['code'] ?? '').isNotEmpty)
                  .toList();
              if (parsed.isNotEmpty) {
                setState(() {
                  _bankList = parsed;
                  // If we already had a selected bank code (from payout details), prefill bank name & code
                  if (_selectedBankCode != null &&
                      _selectedBankCode!.isNotEmpty) {
                    final match = _bankList.firstWhere(
                        (b) => b['code'] == _selectedBankCode,
                        orElse: () => <String, String>{});
                    if (match.isNotEmpty) {
                      _pBankNameCtrl.text = match['name'] ?? '';
                      _pBankCodeCtrl.text = match['code'] ?? '';
                    }
                  }
                });
              }
            }
          }
        } catch (_) {
          // fallback built-in list
          if (_bankList.isEmpty) {
            setState(() {
              _bankList = [
                {'name': 'GTBank', 'code': '058'},
                {'name': 'First Bank', 'code': '011'},
                {'name': 'Zenith Bank', 'code': '057'},
                {'name': 'Access Bank', 'code': '044'},
                {'name': 'UBA', 'code': '033'},
              ];
            });
          }
        }
      }
    } catch (_) {}

    // Prefill controllers
    final pd = _wallet?['payoutDetails'] is Map
        ? Map<String, dynamic>.from(_wallet!['payoutDetails'])
        : null;

    _pNameCtrl.text = pd?['name']?.toString() ?? '';
    _pAccountCtrl.text = pd?['account_number']?.toString() ?? '';
    _pBankNameCtrl.text = pd?['bank_name']?.toString() ?? '';
    _pBankCodeCtrl.text = pd?['bank_code']?.toString() ?? '';
    _selectedBankCode = pd?['bank_code']?.toString() ?? null;
    _pAccountNameCtrl.text = pd?['name']?.toString() ?? '';
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
                return StatefulBuilder(
                  builder: (modalContext, setModalState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                      ),
                      padding: EdgeInsets.fromLTRB(24, 16, 24,
                          MediaQuery.of(context).viewInsets.bottom + 24),
                      child: ListView(
                        controller: controller,
                        children: [
                          Column(
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface
                                        .withAlpha((0.3 * 255).round()),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // 1. Bank name (picker with searchable modal)
                              GestureDetector(
                                onTap: () async {
                                  await _showBankPickerSheet(
                                      onModalRebuild: () =>
                                          setModalState(() {}));
                                  if (modalContext.mounted)
                                    setModalState(() {});
                                },
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    controller: _pBankNameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Bank name',
                                      hintText: 'Select bank',
                                      suffixIcon: Icon(Icons.search),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.onSurface
                                              .withAlpha((0.1 * 255).round()),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.onSurface
                                              .withAlpha((0.1 * 255).round()),
                                        ),
                                      ),
                                    ),
                                    validator: (v) =>
                                        _selectedBankCode == null ||
                                                _selectedBankCode!.isEmpty
                                            ? 'Required'
                                            : null,
                                    readOnly: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // 2. Bank code (read-only auto-filled)
                              TextFormField(
                                controller: _pBankCodeCtrl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Bank code',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              // 3. Account number (manual input)
                              TextFormField(
                                controller: _pAccountCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Account number',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final s = v.trim();
                                  // Cancel previous debounce
                                  _resolveTimer?.cancel();
                                  if (s.length == 10) {
                                    // debounce to avoid rapid requests while typing
                                    _resolveTimer =
                                        Timer(const Duration(milliseconds: 600),
                                            () async {
                                      if (!mounted) return;
                                      await _resolveAccountName(s,
                                          onComplete: () =>
                                              setModalState(() {}));
                                    });
                                  } else {
                                    if (mounted) {
                                      setState(() {
                                        _pAccountNameCtrl.text = '';
                                      });
                                      setModalState(() {});
                                    }
                                  }
                                },
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty)
                                    return 'Required';
                                  final s = v.trim();
                                  if (!RegExp(r'^\d{6,20}$').hasMatch(s))
                                    return 'Enter a valid account number';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              // 4. Account name (filled by lookup, read-only)
                              TextFormField(
                                controller: _pAccountNameCtrl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Account name',
                                  suffix: _isAccountNameLoading
                                      ? SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              // 5. Currency (fixed NGN, read-only)
                              TextFormField(
                                controller: _pCurrencyCtrl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Currency',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.1 * 255).round()),
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _canSavePayoutDetails
                                      ? () async {
                                          if (!_pFormKey.currentState!
                                              .validate()) return;
                                          setModalState(() {
                                            _pSaving = true;
                                          });
                                          try {
                                            await _savePayoutDetails();
                                          } finally {
                                            if (modalContext.mounted) {
                                              setModalState(() {
                                                _pSaving = false;
                                              });
                                            }
                                          }
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor:
                                        theme.colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
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
                                  onPressed: _pSaving
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha((0.6 * 255).round()),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              });
        });
  }

  // Show a searchable bottom sheet for picking a bank. Sheet manages its own
  // loading state so it rebuilds when the API completes.
  // [onModalRebuild] is called when a bank is selected and account is resolved,
  // so the payout sheet can rebuild (modals don't rebuild when parent setState runs).
  Future<void> _showBankPickerSheet({VoidCallback? onModalRebuild}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, controller) => _BankPickerSheetContent(
          selectedBankCode: _selectedBankCode,
          scrollController: controller,
          onBankSelected: (code, name) async {
            setState(() {
              _selectedBankCode = code;
              _pBankNameCtrl.text = name;
              _pBankCodeCtrl.text = code;
            });
            final acct = _pAccountCtrl.text.trim();
            if (acct.length == 10) {
              await _resolveAccountName(acct, onComplete: onModalRebuild);
            }
          },
        ),
      ),
    );
  }

  // Resolve account name for a given account number (tries multiple endpoints and handles non-JSON responses).
  // [onComplete] is called when done so modal sheets can rebuild (they don't rebuild when parent setState runs).
  Future<bool> _resolveAccountName(
    String accountNumber, {
    VoidCallback? onComplete,
  }) async {
    if (accountNumber.trim().isEmpty) return false;
    final s = accountNumber.trim();
    if (!mounted) return false;
    setState(() => _isAccountNameLoading = true);

    try {
      final reqGroupId = _newApiLogId('resolveAcct');
      final token = await TokenStorage.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty)
        headers['Authorization'] = 'Bearer $token';
      if (token == null || token.isEmpty) {
        // Can't authenticate to server; surface a helpful message in debug and return
        if (kDebugMode)
          debugPrint('No auth token available for account resolve');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Unable to verify account: not authenticated')));
        return false;
      }

      final List<Map<String, String>> attempts = [];

      final code = _pBankCodeCtrl.text.trim();

      // If bank code is missing, prefer to remind user to pick a bank first (since docs require bank_code)
      if (code.isEmpty) {
        // Still attempt a resolve without bank_code as a fallback, but inform user in debug
        if (kDebugMode) debugPrint('Attempting resolve without bank_code');
      }

      // Build candidate URIs (GET first)
      final candidates = <Uri>[];
      // Prefer canonical documented endpoint: /api/payments/banks/resolve
      if (code.isNotEmpty) {
        candidates.add(Uri.parse(
            '$API_BASE_URL/api/payments/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}&bank_code=${Uri.encodeQueryComponent(code)}'));
      }
      // Try canonical without bank_code as a fallback
      candidates.add(Uri.parse(
          '$API_BASE_URL/api/payments/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}'));
      // Keep additional fallback variants for backwards compatibility
      if (code.isNotEmpty) {
        candidates.add(Uri.parse(
            '$API_BASE_URL/api/payment/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}&bank_code=${Uri.encodeQueryComponent(code)}'));
        candidates.add(Uri.parse(
            '$API_BASE_URL/payment/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}&bank_code=${Uri.encodeQueryComponent(code)}'));
      }
      candidates.add(Uri.parse(
          '$API_BASE_URL/api/payment/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}'));
      candidates.add(Uri.parse(
          '$API_BASE_URL/payment/banks/resolve?account_number=${Uri.encodeQueryComponent(s)}'));

      Map<String, dynamic>? resolved;

      // Try GET candidates
      var getAttempt = 0;
      for (final uri in candidates) {
        try {
          getAttempt += 1;
          final r = await _loggedHttpCall(
            requestId: '$reqGroupId.get.$getAttempt',
            label: 'wallet.resolveAccountName.get',
            method: 'GET',
            uri: uri,
            headers: headers,
            timeout: const Duration(seconds: 8),
            send: () => http.get(uri, headers: headers),
          );
          final contentType = r.headers['content-type'] ?? '';
          final snippet =
              r.body.length > 200 ? r.body.substring(0, 200) + '...' : r.body;
          attempts.add({
            'uri': uri.toString(),
            'status': r.statusCode.toString(),
            'contentType': contentType,
            'snippet': snippet
          });
          if (r.statusCode >= 200 && r.statusCode < 300 && r.body.isNotEmpty) {
            if (contentType.toLowerCase().contains('application/json') ||
                r.body.trim().startsWith('{') ||
                r.body.trim().startsWith('[')) {
              final dec = jsonDecode(r.body);
              final body = dec is Map ? (dec['data'] ?? dec) : dec;
              if (body is Map) {
                resolved = Map<String, dynamic>.from(body);
                break;
              }
            } else {
              if (kDebugMode)
                debugPrint(
                    'Resolve GET returned non-json ${uri} status=${r.statusCode} content-type=$contentType');
              // continue to next candidate
            }
          }
        } catch (e) {
          attempts.add({
            'uri': uri.toString(),
            'status': 'error',
            'contentType': '',
            'snippet': e.toString()
          });
          if (kDebugMode) debugPrint('GET resolve failed $uri: $e');
        }
      }

      // Try POST variants if GET didn't yield JSON
      if (resolved == null) {
        final postUris = [
          Uri.parse('$API_BASE_URL/api/banks/resolve'),
          Uri.parse('$API_BASE_URL/api/bank/resolve'),
          Uri.parse('$API_BASE_URL/payment/banks/resolve'),
          Uri.parse('$API_BASE_URL/api/payment/banks/resolve')
        ];
        final bodyMap = {'account_number': s, 'bank_code': code};
        var postAttempt = 0;
        for (final uri in postUris) {
          try {
            postAttempt += 1;
            final r = await _loggedHttpCall(
              requestId: '$reqGroupId.post.$postAttempt',
              label: 'wallet.resolveAccountName.post',
              method: 'POST',
              uri: uri,
              headers: headers,
              body: bodyMap,
              timeout: const Duration(seconds: 8),
              send: () =>
                  http.post(uri, headers: headers, body: jsonEncode(bodyMap)),
            );
            final contentType = r.headers['content-type'] ?? '';
            final snippet =
                r.body.length > 200 ? r.body.substring(0, 200) + '...' : r.body;
            attempts.add({
              'uri': uri.toString(),
              'status': r.statusCode.toString(),
              'contentType': contentType,
              'snippet': snippet
            });
            if (r.statusCode >= 200 &&
                r.statusCode < 300 &&
                r.body.isNotEmpty) {
              if (contentType.toLowerCase().contains('application/json') ||
                  r.body.trim().startsWith('{') ||
                  r.body.trim().startsWith('[')) {
                final dec = jsonDecode(r.body);
                final body = dec is Map ? (dec['data'] ?? dec) : dec;
                if (body is Map) {
                  resolved = Map<String, dynamic>.from(body);
                  break;
                }
              } else {
                if (kDebugMode)
                  debugPrint(
                      'Resolve POST returned non-json ${uri} status=${r.statusCode} content-type=$contentType');
              }
            }
          } catch (e) {
            attempts.add({
              'uri': uri.toString(),
              'status': 'error',
              'contentType': '',
              'snippet': e.toString()
            });
            if (kDebugMode) debugPrint('POST resolve failed $uri: $e');
          }
        }
      }

      if (resolved != null) {
        final name = resolved['account_name'] ??
            resolved['accountName'] ??
            resolved['name'];
        if (name != null) {
          if (mounted)
            setState(() {
              _pAccountNameCtrl.text = name.toString();
            });
          return true;
        }
      }
      // If we reached here without a result, show a concise debug summary of attempts
      if (kDebugMode && mounted) {
        final lines = attempts
            .take(4)
            .map((a) => '${a['status']} ${a['uri']}')
            .join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resolve failed for: \n$lines')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _isAccountNameLoading = false);
      onComplete?.call();
    }
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
      final uri =
          Uri.parse('$base/api/transactions?page=$_txPage&limit=$_txLimit');
      if (kDebugMode)
        debugPrint('[UserWalletpage] Loading more transactions from: $uri');
      try {
        final reqId = _newApiLogId('transactions');
        final resp = await _loggedHttpCall(
          requestId: '$reqId.getPage',
          label: 'wallet.transactions.loadMore',
          method: 'GET',
          uri: uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          timeout: const Duration(seconds: 10),
          send: () => http.get(uri, headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          }),
        );
        if (kDebugMode)
          debugPrint(
              '[UserWalletpage] Load more transactions response: ${resp.statusCode} ${resp.body}');
        if (resp.statusCode >= 200 &&
            resp.statusCode < 300 &&
            resp.body.isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final list = decoded is Map
              ? (decoded['data'] ??
                  decoded['transactions'] ??
                  decoded['results'] ??
                  decoded)
              : decoded;
          if (list is List && list.isNotEmpty) {
            final additional = List<Map<String, dynamic>>.from(list.map(
                (e) => e is Map ? Map<String, dynamic>.from(e) : {'raw': e}));
            final prof = AppStateNotifier.instance.profile;
            final myId =
                (prof?['_id'] ?? prof?['id'] ?? prof?['userId'])?.toString();
            if (myId != null && myId.isNotEmpty) {
              _transactions.addAll(additional
                  .where((tx) => _transactionBelongsToUser(tx, myId)));
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
    } catch (_) {
    } finally {
      setState(() => _txLoadingMore = false);
    }
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
          : (_wallet!['currency'] ??
              _wallet!['currencyCode'] ??
              _wallet!['currency_code']);
      final currencyCode =
          (walletCurrency is String && walletCurrency.isNotEmpty)
              ? walletCurrency.toUpperCase()
              : 'NGN';

      try {
        // Use simpleCurrency so symbol is localized where possible
        final formatter = NumberFormat.simpleCurrency(name: currencyCode);
        // Format without decimals for whole currency units
        return formatter.format(number.round());
      } catch (_) {
        // Fallback: use grouping and a simple symbol map
        final formatter = NumberFormat.decimalPattern();
        final symbolMap = <String, String>{
          'NGN': '₦',
          'USD': '\$',
          'EUR': '€',
          'GBP': '£'
        };
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

    final title =
        transaction['title']?.toString() ?? (isCredit ? 'Payout' : 'Payment');
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                color:
                    theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              date,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withAlpha((0.4 * 255).round()),
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

  // Helper to extract a stable transaction id from a transaction map
  String _txId(Map<String, dynamic> tx) {
    return (tx['_id'] ??
            tx['id'] ??
            tx['transactionId'] ??
            tx['reference'] ??
            tx['ref'] ??
            tx['txId'] ??
            '')
        .toString();
  }

  // Helper to determine if a transaction belongs to the logged-in user
  bool _transactionBelongsToUser(Map<String, dynamic> tx, String? myId) {
    // If we don't have a logged-in user's id, be conservative and treat
    // transactions as not belonging to the current user. Returning `true` here
    // may show other users' transactions in multi-tenant responses.
    if (myId == null || myId.isEmpty) return false;

    final candidateKeys = [
      'userId',
      'user_id',
      'user',
      'customerId',
      'customer_id',
      'recipientId',
      'recipient',
      'clientId',
      'artisanId',
      'ownerId',
      'from',
      'to',
      'account',
      'accountId',
      'walletId',
      'customer',
      'owner',
      'createdBy'
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                      color:
                          colorScheme.onSurface.withAlpha((0.8 * 255).round()),
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
                              valueColor:
                                  AlwaysStoppedAnimation(colorScheme.onSurface),
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
                              color: colorScheme.onSurface
                                  .withAlpha((0.1 * 255).round()),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Balance',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface
                                            .withAlpha((0.7 * 255).round()),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        // Eye icon to hide/unhide balance
                                        IconButton(
                                          tooltip: _hideBalance
                                              ? 'Show balance'
                                              : 'Hide balance',
                                          icon: Icon(
                                              _hideBalance
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                              size: 20),
                                          color: colorScheme.onSurface
                                              .withAlpha((0.8 * 255).round()),
                                          onPressed: _toggleBalanceVisibility,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary
                                                .withAlpha((0.1 * 255).round()),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons
                                                .account_balance_wallet_rounded,
                                            color: colorScheme.primary,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _loading
                                    ? Container(
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: colorScheme.onSurface
                                              .withAlpha((0.1 * 255).round()),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      )
                                    : Text(
                                        _hideBalance
                                            ? '*****'
                                            : _formatAmount(
                                                _wallet?['total'] ??
                                                    _wallet?['balance'] ??
                                                    _wallet?['totalEarned'] ??
                                                    _wallet?['totalSpent'] ??
                                                    0,
                                              ),
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 32,
                                        ),
                                      ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Available',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withAlpha(
                                                      (0.6 * 255).round()),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _loading
                                              ? Container(
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.onSurface
                                                        .withAlpha((0.1 * 255)
                                                            .round()),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                )
                                              : Text(
                                                  _formatAmount(_wallet?[
                                                          'available'] ??
                                                      _wallet?[
                                                          'availableBalance'] ??
                                                      _wallet?['balance'] ??
                                                      0),
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pending',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withAlpha(
                                                      (0.6 * 255).round()),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _loading
                                              ? Container(
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.onSurface
                                                        .withAlpha((0.1 * 255)
                                                            .round()),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                )
                                              : Text(
                                                  _formatAmount(_wallet?[
                                                          'pending'] ??
                                                      _wallet?[
                                                          'pendingAmount'] ??
                                                      0),
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
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
                            padding:
                                const EdgeInsets.only(left: 4.0, bottom: 12),
                            child: Text(
                              'PAYOUT ACCOUNT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface
                                    .withAlpha((0.6 * 255).round()),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.onSurface
                                    .withAlpha((0.1 * 255).round()),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Payout Details',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _pEditLoading
                                            ? null
                                            : () async {
                                                setState(
                                                    () => _pEditLoading = true);
                                                try {
                                                  await _showPayoutDetailsSheet(
                                                      isEdit: true);
                                                } finally {
                                                  if (mounted)
                                                    setState(() =>
                                                        _pEditLoading = false);
                                                }
                                              },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          minimumSize: const Size(48, 48),
                                        ),
                                        child: _pEditLoading
                                            ? SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: colorScheme.primary,
                                                ),
                                              )
                                            : Text(
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
                                  if (_wallet != null &&
                                      _wallet!['payoutDetails'] != null) ...[
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Account Name',
                                      value: _wallet!['payoutDetails']['name']
                                              ?.toString() ??
                                          '—',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Account Number',
                                      value: _wallet!['payoutDetails']
                                                  ['account_number']
                                              ?.toString() ??
                                          '—',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildDetailRow(
                                      context: context,
                                      label: 'Bank',
                                      value: _wallet!['payoutDetails']
                                                  ['bank_name']
                                              ?.toString() ??
                                          '—',
                                    ),
                                  ] else ...[
                                    Text(
                                      'No payout details set',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface
                                            .withAlpha((0.6 * 255).round()),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () => _showPayoutDetailsSheet(
                                          isEdit: false),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        minimumSize:
                                            const Size(double.infinity, 0),
                                      ),
                                      child: Text('Add Account Details'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Recent Transactions Section with tabs (Pending / Completed)
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0, bottom: 12),
                          child: Text(
                            'RECENT TRANSACTIONS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface
                                  .withAlpha((0.6 * 255).round()),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        // Tabbed view for Pending / Completed
                        DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.black
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: colorScheme.onSurface
                                          .withAlpha((0.06 * 255).round())),
                                ),
                                child: TabBar(
                                  labelColor: colorScheme.primary,
                                  unselectedLabelColor: colorScheme.onSurface
                                      .withAlpha((0.6 * 255).round()),
                                  indicatorColor: colorScheme.primary,
                                  tabs: const [
                                    Tab(text: 'Pending'),
                                    Tab(text: 'Completed'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Tab views
                              SizedBox(
                                // limit height so inner lists scroll independently
                                height: 420,
                                child: TabBarView(
                                  children: [
                                    // Pending
                                    Builder(builder: (ctx) {
                                      final pending = _transactions.where((t) {
                                        final status = (t['status'] ??
                                                t['transactionStatus'] ??
                                                '')
                                            .toString()
                                            .toLowerCase();
                                        return status.contains('pending') ||
                                            status.contains('holding') ||
                                            status.contains('processing');
                                      }).toList();

                                      if (_loading && pending.isEmpty) {
                                        return ListView(
                                          padding: EdgeInsets.zero,
                                          children: List.generate(
                                              3,
                                              (_) => _buildTransactionSkeleton(
                                                  context)),
                                        );
                                      }

                                      if (!_loading && pending.isEmpty) {
                                        return Center(
                                          child: Card(
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(24.0),
                                              child: Text(
                                                  'No pending transactions',
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                          color: colorScheme
                                                              .onSurface
                                                              .withAlpha((0.6 *
                                                                      255)
                                                                  .round()))),
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: pending.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (ctx2, i) {
                                          final tx = pending[i];
                                          return InkWell(
                                            onTap: () =>
                                                _showTransactionDetails(tx),
                                            child: _buildTransactionItem(tx),
                                          );
                                        },
                                      );
                                    }),

                                    // Completed
                                    Builder(builder: (ctx) {
                                      final completed =
                                          _transactions.where((t) {
                                        final status = (t['status'] ??
                                                t['transactionStatus'] ??
                                                '')
                                            .toString()
                                            .toLowerCase();
                                        return !(status.contains('pending') ||
                                            status.contains('holding') ||
                                            status.contains('processing'));
                                      }).toList();

                                      if (_loading && completed.isEmpty) {
                                        return ListView(
                                          padding: EdgeInsets.zero,
                                          children: List.generate(
                                              3,
                                              (_) => _buildTransactionSkeleton(
                                                  context)),
                                        );
                                      }

                                      if (!_loading && completed.isEmpty) {
                                        return Center(
                                          child: Card(
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(24.0),
                                              child: Text(
                                                  'No completed transactions',
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                          color: colorScheme
                                                              .onSurface
                                                              .withAlpha((0.6 *
                                                                      255)
                                                                  .round()))),
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: completed.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (ctx2, i) {
                                          final tx = completed[i];
                                          return InkWell(
                                            onTap: () =>
                                                _showTransactionDetails(tx),
                                            child: _buildTransactionItem(tx),
                                          );
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              ),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                color:
                    theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
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
                color:
                    theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 20,
              width: 70,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()),
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

  // Show transaction details bottom sheet
  Future<void> _showTransactionDetails(Map<String, dynamic> transaction) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ff = FlutterFlowTheme.of(context);

    // Format date for display
    String formatDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return 'Unknown date';
      try {
        final date = DateTime.parse(dateStr);
        return DateFormat.yMMMd().add_jm().format(date);
      } catch (_) {
        return dateStr;
      }
    }

    // Extract and format transaction details
    final title = transaction['title']?.toString() ?? 'Transaction';
    final description = transaction['description']?.toString() ?? '';
    final amount = transaction['amount'] ?? transaction['value'] ?? 0;
    final date = formatDate(transaction['date']?.toString() ?? '');
    final status = (transaction['status'] ?? '').toString().toLowerCase();
    final statusLabel = status.isNotEmpty
        ? (status[0].toUpperCase() + status.substring(1))
        : 'Unknown';
    final isCredit = transaction['type'] == 'credit';

    // Show bottom sheet
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, controller) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.black : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: ListView(
                  controller: controller,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.3 * 255).round()),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withAlpha((0.6 * 255).round()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Amount',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withAlpha((0.7 * 255).round()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isCredit ? '+' : '-'}${_formatAmount(amount)}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Status',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withAlpha((0.7 * 255).round()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCredit
                            ? ff.success.withAlpha((0.1 * 255).round())
                            : ff.error.withAlpha((0.1 * 255).round()),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isCredit ? 'Credit' : 'Debit',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isCredit ? ff.success : ff.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Show textual transaction status (e.g., Pending, Completed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withAlpha((0.7 * 255).round()),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Description',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withAlpha((0.7 * 255).round()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withAlpha((0.8 * 255).round()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text('Close'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        });
  }
}
