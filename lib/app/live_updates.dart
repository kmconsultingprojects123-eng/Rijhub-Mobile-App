import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ticks whenever something new happens to the signed-in person: a request
/// for an artisan, a client's booking accepted, a payment released. Every
/// one of those lands in their inbox, whose unread count the API keeps live,
/// so the screens that list them reload on this instead of waiting for a
/// pull to refresh.
class LiveUpdates extends ChangeNotifier {
  LiveUpdates(Stream<int> inboxUnread) {
    _subscription = inboxUnread.listen((count) {
      final changed = _count != null && count != _count;
      _count = count;
      if (changed) notifyListeners();
    }, onError: (Object _) {});
  }

  late final StreamSubscription<int> _subscription;
  int? _count;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
