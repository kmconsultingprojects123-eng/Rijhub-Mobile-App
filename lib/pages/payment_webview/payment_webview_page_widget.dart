import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import '../../services/webview_monitor.dart';

class PaymentWebviewPageWidget extends StatefulWidget {
  final String url;
  final String? successUrlContains; // if the gateway redirects to a url containing this, we treat as success

  const PaymentWebviewPageWidget({super.key, required this.url, this.successUrlContains});

  @override
  State<PaymentWebviewPageWidget> createState() => _PaymentWebviewPageWidgetState();
}

class _PaymentWebviewPageWidgetState extends State<PaymentWebviewPageWidget> {
  WebViewController? _controller;
  bool _loading = true;
  bool _blockingClose = false;
  bool _initFailed = false;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) debugPrint('PaymentWebview:initState called for url=${widget.url}');
    // Immediately mark opened so the payment initiator knows the page exists.
    try { WebviewMonitor.markOpened(); } catch (_) {}

    // Create the controller after first frame to avoid platform channel races
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (Platform.isAndroid) {
          if (kDebugMode) debugPrint('PaymentWebview: running on Android — relying on plugin default platform implementation');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PaymentWebview: platform init warning: $e');
      }

      try {
        if (kDebugMode) debugPrint('PaymentWebview: init controller for url=${widget.url}');
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(NavigationDelegate(
            onPageStarted: (s) {
              if (!mounted) return;
              try {
                if (kDebugMode) debugPrint('PaymentWebview:onPageStarted -> $s');
                _lastUrl = s;
                setState(() => _loading = true);
              } catch (_) {}
            },
            onPageFinished: (s) {
              if (!mounted) return;
              try {
                if (kDebugMode) debugPrint('PaymentWebview:onPageFinished -> $s');
                _lastUrl = s;
                setState(() => _loading = false);
                // If caller provided a success marker, honor it first
                if (widget.successUrlContains != null && s.contains(widget.successUrlContains!)) {
                  if (kDebugMode) debugPrint('PaymentWebview: detected success marker ${widget.successUrlContains} in $s');
                  if (mounted) Navigator.of(context).pop({'success': true, 'url': s});
                  return;
                }
                // Normalize to lower-case for simple checks
                final lower = s.toLowerCase();
                // Try to parse URL and detect reference or tx_ref query parameter (common Paystack redirect)
                try {
                  final uri = Uri.tryParse(s);
                  if (uri != null) {
                    final qref = uri.queryParameters['reference'] ?? uri.queryParameters['ref'] ?? uri.queryParameters['tx_ref'];
                    if (qref != null && qref.isNotEmpty) {
                      if (kDebugMode) debugPrint('PaymentWebview: detected reference query param -> $qref');
                      if (mounted) Navigator.of(context).pop({'success': true, 'url': s});
                      return;
                    }
                  }
                } catch (_) {}
                // Also look for common success markers in the URL or HTML finish string
                if (lower.contains('status=success') || lower.contains('successful') || lower.contains('payment successful') || (lower.contains('gateway_response') && lower.contains('successful'))) {
                  if (kDebugMode) debugPrint('PaymentWebview: detected success markers in url/fragment');
                  if (mounted) Navigator.of(context).pop({'success': true, 'url': s});
                  return;
                }

                // Detect common failure/cancellation markers (Paystack and other gateways)
                // Examples: status=failed, status=cancelled, /cancel path, payment_failed, transaction=failed, 'failed' without 'success'
                final isFailure = (lower.contains('status=failed') || lower.contains('status=cancel') || lower.contains('status=cancelled') || lower.contains('/cancel') || lower.contains('payment_failed') || lower.contains('transaction=failed') || (lower.contains('failed') && !lower.contains('success')));
                if (isFailure) {
                  if (kDebugMode) debugPrint('PaymentWebview: detected failure/cancel marker in url -> $s');
                  if (mounted) Navigator.of(context).pop({'success': false, 'url': s});
                  return;
                }
              } catch (_) {}
            },
            onNavigationRequest: (req) {
              // Log every navigation request. If the link is an external scheme, open externally.
              try {
                if (kDebugMode) debugPrint('PaymentWebview:onNavigationRequest -> ${req.url}');
                final uri = Uri.tryParse(req.url);
                if (uri != null && (uri.scheme == 'tel' || uri.scheme == 'mailto')) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationDecision.prevent;
                }
              } catch (_) {}
              return NavigationDecision.navigate;
            },
          ));

        if (kDebugMode) debugPrint('PaymentWebview: controller created, marking opened -> ${widget.url}');
        // Mark opened as soon as the controller exists so the starter knows the page is present.
        WebviewMonitor.markOpened();
        if (kDebugMode) debugPrint('PaymentWebview: loading request -> ${widget.url}');
        await controller.loadRequest(Uri.parse(widget.url));
        // Also mark opened again after load completes (defensive)
        WebviewMonitor.markOpened();

        if (!mounted) return;
        setState(() {
          _controller = controller;
          _loading = false;
        });
      } catch (e) {
        // Platform channel error — mark init failed and fallback to external browser
        if (kDebugMode) debugPrint('WebView init failed: $e');
        setState(() {
          _initFailed = true;
          _loading = false;
        });
        // Do NOT automatically open external browser here. Show UI so the user
        // can choose to open externally. Auto-launching causes the app to go to
        // background which is undesirable during payment.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        // If a pop was attempted but not performed (didPop == false), ask the user for confirmation
        if (!didPop) {
          final shouldClose = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Cancel payment?'),
            content: const Text('Are you sure you want to cancel the payment? Your transaction will be aborted.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
            ],
          ));
          if (shouldClose == true) {
            try { Navigator.of(context).pop({'success': false, 'url': _lastUrl ?? widget.url}); } catch (_) {}
          }
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
            onPressed: _blockingClose
                ? null
                : () async {
                    final shouldClose = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: const Text('Cancel payment?'),
                          content: const Text('Are you sure you want to cancel the payment? Your transaction will be aborted.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
                            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
                          ],
                        ));
                    if (shouldClose == true) {
                      try { Navigator.of(context).pop({'success': false, 'url': _lastUrl ?? widget.url}); } catch (_) {}
                    }
                  },
          ),
        ),
        body: Stack(children: [
          // If init failed show a simple message and a button to open external browser
          if (_initFailed) ...[
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Unable to open in-app payment. Opening in browser...'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () async {
                try {
                  final uri = Uri.parse(widget.url);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }, child: const Text('Open in browser'))
            ])),
          ] else ...[
            if (_controller != null) Positioned.fill(child: WebViewWidget(controller: _controller!)) else const SizedBox.shrink(),
          ],
          if (_loading) const Center(child: CircularProgressIndicator()),
        ]),
      ),
    );
  }
}
