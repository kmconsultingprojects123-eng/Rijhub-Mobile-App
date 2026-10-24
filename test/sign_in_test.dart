import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/data/repositories/repositories.dart';

import 'support/app_harness.dart';

/// A code waiting to be typed, sent by [channel].
OtpChallenge _sent(OtpChannel channel) => OtpChallenge(
      phone: '+2348031234567',
      channel: channel,
      requestId: 'test',
      resendAvailableAt: DateTime.now().add(const Duration(seconds: 30)),
    );

void main() {
  appTest('a code on WhatsApp shows the Flutterwave message to look for',
      (t) async {
    final app = await launch(t, as: As.guestClient);
    app.authFlow.restoreChallenge('8031234567', _sent(OtpChannel.whatsapp));
    await tapText(t, 'Sign in', exact: true);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Check WhatsApp for a message from Flutterwave:'),
        findsOneWidget);
    expect(
        find.bySemanticsLabel(
            RegExp('^Example: a WhatsApp message from Flutterwave')),
        findsOneWidget);
  });

  appTest('a texted code shows no WhatsApp example', (t) async {
    final app = await launch(t, as: As.guestClient);
    app.authFlow.restoreChallenge('8031234567', _sent(OtpChannel.sms));
    await tapText(t, 'Sign in', exact: true);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.textContaining('Flutterwave'), findsNothing);
  });
}
