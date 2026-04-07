import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../../services/webview_monitor.dart';

class PaymentWebviewPageWidget extends StatefulWidget {
  final String url;
  final String? successUrlContains;
  final String? expectedReference;

  const PaymentWebviewPageWidget({
    super.key,
    required this.url,
    this.successUrlContains,
    this.expectedReference,
  });

  @override
  State<PaymentWebviewPageWidget> createState() =>
      _PaymentWebviewPageWidgetState();
}

class _PaymentWebviewPageWidgetState extends State<PaymentWebviewPageWidget> {
  WebViewController? _controller;
  bool _loading = true;
  bool _blockingClose = false;
  bool _initFailed = false;
  bool _completed = false;
  String? _lastUrl;

  bool _isCheckoutHost(Uri? uri) {
    final host = uri?.host.toLowerCase() ?? '';
    return host.contains('paystack') || host.contains('checkout');
  }

  String? _extractReference(String url) {
    try {
      final uri = Uri.tryParse(url);
      return uri?.queryParameters['reference'] ??
          uri?.queryParameters['ref'] ??
          uri?.queryParameters['tx_ref'] ??
          uri?.queryParameters['trxref'];
    } catch (_) {
      return null;
    }
  }

  String? _resolvedReference(String url) {
    return _extractReference(url) ?? widget.expectedReference;
  }

  bool _isSuccessUrl(String url) {
    if (url.trim().isEmpty || url == 'about:blank') {
      return false;
    }

    if (widget.successUrlContains != null &&
        url.contains(widget.successUrlContains!)) {
      return true;
    }

    final lower = url.toLowerCase();
    if (lower.contains('status=success') ||
        lower.contains('payment successful') ||
        lower.contains('payment_successful') ||
        lower.contains('gateway_response=successful')) {
      return true;
    }

    final uri = Uri.tryParse(url);
    final reference = _extractReference(url);
    return reference != null &&
        reference.isNotEmpty &&
        uri != null &&
        !_isCheckoutHost(uri);
  }

  bool _isFailureUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('status=failed') ||
        lower.contains('status=cancel') ||
        lower.contains('status=cancelled') ||
        lower.contains('/cancel') ||
        lower.contains('payment_failed') ||
        lower.contains('transaction=failed') ||
        (lower.contains('failed') && !lower.contains('success'));
  }

  void _completePayment({
    required bool success,
    required String url,
    String? reference,
  }) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop({
      'success': success,
      'url': url,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (Platform.isAndroid) {
          // Rely on plugin defaults; no extra Android-specific setup needed here.
        }
      } catch (_) {}

      try {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                if (!mounted || _completed) return;
                _lastUrl = url;
                setState(() => _loading = true);
              },
              onPageFinished: (url) {
                if (!mounted || _completed) return;
                _lastUrl = url;
                setState(() => _loading = false);

                final reference = _resolvedReference(url);
                if (_isSuccessUrl(url)) {
                  _completePayment(
                    success: true,
                    url: url,
                    reference: reference,
                  );
                  return;
                }

                if (_isFailureUrl(url)) {
                  _completePayment(
                    success: false,
                    url: url,
                    reference: reference,
                  );
                }
              },
              onNavigationRequest: (req) {
                _lastUrl = req.url;
                final uri = Uri.tryParse(req.url);
                if (uri != null &&
                    (uri.scheme == 'tel' || uri.scheme == 'mailto')) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationDecision.prevent;
                }
                final reference = _resolvedReference(req.url);
                if (_isSuccessUrl(req.url)) {
                  _completePayment(
                    success: true,
                    url: req.url,
                    reference: reference,
                  );
                  return NavigationDecision.prevent;
                }
                if (_isFailureUrl(req.url)) {
                  _completePayment(
                    success: false,
                    url: req.url,
                    reference: reference,
                  );
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            ),
          );

        await controller.loadRequest(Uri.parse(widget.url));
        WebviewMonitor.markOpened();

        if (!mounted) return;
        setState(() {
          _controller = controller;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _initFailed = true;
          _loading = false;
        });
      }
    });
  }

  Future<void> _confirmClose() async {
    if (_completed) return;

    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: const Text(
          'Are you sure you want to cancel the payment? Your transaction will be aborted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldClose == true) {
      _completePayment(success: false, url: _lastUrl ?? widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          await _confirmClose();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          foregroundColor: FlutterFlowTheme.of(context).primary,
          elevation: 0,
          title: const Text('Complete Payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _blockingClose ? null : _confirmClose,
          ),
        ),
        body: Stack(
          children: [
            if (_initFailed) ...[
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to open in-app payment.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final uri = Uri.parse(widget.url);
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      },
                      child: const Text('Open in browser'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (_controller != null)
                Positioned.fill(child: WebViewWidget(controller: _controller!))
              else
                const SizedBox.shrink(),
            ],
            if (_loading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
