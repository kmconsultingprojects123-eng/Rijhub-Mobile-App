/// Simple, process-wide guard for long-running UI flows (payments, uploads).
/// This is intentionally tiny: a global flag that callers can set when a critical
/// flow is active so navigation helpers can defer disruptive "replace-all"
/// navigations until the flow completes.
class FlowGuard {
  FlowGuard._();

  static bool _paymentActive = false;

  static bool get isPaymentActive => _paymentActive;

  static void setPaymentActive(bool v) {
    _paymentActive = v;
  }
}
