import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../api_config.dart';
import '../../services/token_storage.dart';
import '../../utils/app_notification.dart';

class SubmitQuotePage extends StatefulWidget {
  final String jobId;
  final Color primaryColor;

  const SubmitQuotePage({super.key, required this.jobId, required this.primaryColor});

  @override
  State<SubmitQuotePage> createState() => _SubmitQuotePageState();
}

class _SubmitQuotePageState extends State<SubmitQuotePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitQuote() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final token = await TokenStorage.getToken();
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        AppNotification.showError(context, 'You must be signed in to submit a quote.');
        return;
      }

      final amountRaw = _amountController.text.trim();
      final amount = num.tryParse(amountRaw.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
      final notes = _noteController.text.trim();

      // Build a minimal quote payload per API docs (quote-only)
      final body = {
        'items': [
          {'name': 'Service', 'cost': amount, 'qty': 1}
        ],
        'serviceCharge': 0,
        'notes': notes,
      };

      final base = API_BASE_URL.replaceAll(RegExp(r'/+\$'), '');
      final uri = Uri.parse('$base/api/jobs/${widget.jobId}/quotes');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

      final resp = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        final success = decoded is Map ? (decoded['success'] == true) : false;
        if (success) {
          AppNotification.showSuccess(context, 'Quote submitted');
          // Return to caller (true) so callers can refresh lists.
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        final msg = decoded is Map ? (decoded['message'] ?? decoded['error']?.toString() ?? 'Failed to submit quote') : 'Failed to submit quote';
        AppNotification.showError(context, msg.toString());
      } else {
        AppNotification.showError(context, 'Failed to submit quote (status ${resp.statusCode})');
      }
    } catch (e) {
      if (mounted) AppNotification.showError(context, 'Error submitting quote: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;

    // Adaptive container color
    final containerColor = isDark ? theme.cardColor : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Quote'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 720 : screenWidth - 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Submit a quote for this job', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      // Informational note
                      Text(
                        'Provide the total amount you propose and an optional note for the job owner. This will create a quote associated with the job for the owner to review.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 16),
                      // Amount field
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (NGN)',
                          prefixText: '₦',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? theme.cardColor : Colors.grey[50],
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter amount';
                          final n = num.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), ''));
                          if (n == null || n <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Note field
                      TextFormField(
                        controller: _noteController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Note (optional)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? theme.cardColor : Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Submit button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submitQuote,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit Quote'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
