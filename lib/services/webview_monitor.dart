import 'dart:async';
import 'package:flutter/foundation.dart';

/// Simple in-memory monitor used to detect whether a payment webview actually
/// initialized. Callers should call `WebviewMonitor.start()` before pushing the
/// webview page and then await `waitOpened` for a short timeout. The
/// webview page should call `WebviewMonitor.markOpened()` as soon as its
/// controller is created / request is loaded.
class WebviewMonitor {
  static Completer<void>? _c;

  static void start() {
    debugPrint('WebviewMonitor.start()');
    _c = Completer<void>();
  }

  static void markOpened() {
    try {
      debugPrint('WebviewMonitor.markOpened() — completer present=${_c != null}');
      if (_c != null && !_c!.isCompleted) _c!.complete();
    } catch (_) {}
  }

  static Future<bool> waitOpened({Duration timeout = const Duration(seconds: 3)}) async {
    final c = _c;
    debugPrint('WebviewMonitor.waitOpened() — completer present=${c != null}, timeout=${timeout.inSeconds}s');
    if (c == null) return false;
    try {
      await c.future.timeout(timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      _c = null;
    }
  }
}
