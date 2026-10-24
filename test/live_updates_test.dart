import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/app/live_updates.dart';

void main() {
  test('ticks when the inbox changes, not on the first count', () async {
    final inbox = StreamController<int>();
    final live = LiveUpdates(inbox.stream);
    var ticks = 0;
    live.addListener(() => ticks++);
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    inbox.add(2);
    await settle();
    expect(ticks, 0);

    inbox.add(3); // a new request, say
    await settle();
    expect(ticks, 1);

    inbox.add(3);
    await settle();
    expect(ticks, 1);

    live.dispose();
    await inbox.close();
  });
}
