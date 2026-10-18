import 'package:flutter/widgets.dart';

import '../features/booking/paystack_checkout.dart';

/// Taking a payment. Screens ask [hosted] to know whether the app's own pay
/// sheet is the payment (sample data) or whether the payment partner's
/// checkout opens as part of booking (the API), so nobody is asked to pay
/// twice.
abstract interface class PaymentGateway {
  /// True when booking opens the payment partner's checkout page itself.
  bool get hosted;

  /// Opens the checkout at [url] and completes true once it comes back to
  /// [callback] (paid, or so the page says: the API checks with Paystack
  /// either way), false when the person closes it.
  Future<bool> checkout(Uri url, {required Uri callback});
}

/// Sample data: the app's pay sheet stands in for the checkout.
class SamplePaymentGateway implements PaymentGateway {
  const SamplePaymentGateway();

  @override
  bool get hosted => false;

  @override
  Future<bool> checkout(Uri url, {required Uri callback}) async => true;
}

/// Paystack's hosted checkout (card, bank transfer, USSD), in a page over
/// the app.
class PaystackPaymentGateway implements PaymentGateway {
  PaystackPaymentGateway(this._navigator);

  final GlobalKey<NavigatorState> _navigator;

  @override
  bool get hosted => true;

  @override
  Future<bool> checkout(Uri url, {required Uri callback}) async {
    final navigator = _navigator.currentState;
    if (navigator == null) return false;
    final paid = await navigator.push<bool>(PageRouteBuilder(
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) =>
          PaystackCheckoutPage(url: url, callback: callback),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation),
        child: child,
      ),
    ));
    return paid ?? false;
  }
}
