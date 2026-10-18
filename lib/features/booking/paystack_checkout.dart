import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/theme.dart';
import '../shared/page.dart';

/// Paystack's checkout, in the app: card, bank transfer or USSD. It closes
/// by itself when Paystack sends the person back to RijHub's callback
/// address; the payment is then checked with Paystack by the API.
class PaystackCheckoutPage extends StatefulWidget {
  const PaystackCheckoutPage(
      {super.key, required this.url, required this.callback});

  final Uri url;

  /// Where Paystack returns to once the payment is done.
  final Uri callback;

  @override
  State<PaystackCheckoutPage> createState() => _PaystackCheckoutPageState();
}

class _PaystackCheckoutPageState extends State<PaystackCheckoutPage> {
  late final WebViewController _web;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final to = Uri.tryParse(request.url);
          if (to != null && _isCallback(to)) {
            _finish(true);
            return NavigationDecision.prevent;
          }
          // Paystack's own "cancel payment" leaves the checkout this way.
          if (to != null &&
              to.host.endsWith('paystack.co') &&
              to.path.startsWith('/close')) {
            _finish(false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(widget.url);
  }

  bool _isCallback(Uri to) =>
      to.host == widget.callback.host &&
      to.path.startsWith(widget.callback.path);

  void _finish(bool paid) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(paid);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(false);
      },
      child: PageScaffold(
        title: 'Pay securely',
        subtitle: 'Paystack',
        onBack: () => _finish(false),
        body: Stack(
          children: [
            WebViewWidget(controller: _web),
            if (_loading) LinearProgressIndicator(color: c.brand, minHeight: 2),
          ],
        ),
      ),
    );
  }
}
