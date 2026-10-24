// For people who'd rather listen than read: the Ask chat reads its messages
// aloud and says what to tap, stops once they type a problem, starts again
// when they talk, and the speaker button turns it off for good. An artisan
// can just say they want work.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/app/speech.dart';
import 'package:rijhub/data/models/models.dart';

import 'support/app_harness.dart';

/// What the app read aloud.
List<String> said(Launched app) => (app.deps.speaker as SampleSpeaker).said;

Future<void> typeAndSend(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField).last, text);
  await t.testTextInput.receiveAction(TextInputAction.send);
  await wait(t, 3);
}

void main() {
  appTest('the welcome is read aloud, with where to talk', (t) async {
    final app = await launch(t, as: As.firstOpen);

    expect(said(app).first, startsWith("Hi! I'm Employee."));
    expect(said(app).last, endsWith('To talk to me, tap the red microphone.'));
  });

  appTest('the welcome tells an artisan their way in, too', (t) async {
    final app = await launch(t, as: As.firstOpen);

    expect(find.textContaining('Are you an artisan looking for work?'),
        findsOneWidget);
    expect(said(app).last, startsWith('Are you an artisan looking for work?'));
  });

  appTest('an artisan who says their trade on the welcome joins that way',
      (t) async {
    final app = await launch(t, as: As.firstOpen);

    await typeAndSend(t, "I'm a plumber");

    expect(find.textContaining('Got it: Plumbing.'), findsOneWidget);
    expect(find.text('Join free'), findsOneWidget);
    expect(find.text('Best match'), findsNothing);
    await tapText(t, 'Join free', then: 2);
    expect(app.session.role, UserRole.artisan);
  });

  appTest('a tapped problem is answered aloud, with what to tap next',
      (t) async {
    final app = await launch(t, as: As.firstOpen);
    said(app).clear();

    await tapText(t, 'AC not cooling', then: 3);

    expect(said(app).first, contains('8,000 to 12,000 naira'));
    expect(said(app).last, 'To book Emeka, tap the black button.');
  });

  appTest('a problem typed in words stops the reading aloud', (t) async {
    final app = await launch(t, as: As.firstOpen);
    said(app).clear();

    await typeAndSend(t, 'my generator will not start');

    expect(find.text('Best match'), findsOneWidget);
    expect(said(app), isEmpty);
  });

  appTest('a voice note turns the reading aloud back on', (t) async {
    final app = await launch(t, as: As.firstOpen);
    await typeAndSend(t, 'my generator will not start');
    said(app).clear();

    await tapLabel(t, 'Record a voice note', then: 0.5);
    await tapLabel(t, 'Send voice note', then: 4);

    expect(said(app), isNotEmpty);
    expect(said(app).last, 'To book Emeka, tap the black button.');
  });

  appTest('the speaker button turns it off, and it stays off', (t) async {
    final app = await launch(t, as: As.firstOpen);

    await tapLabel(t, 'Stop reading aloud', then: 0.5);
    expect(app.session.readAloud, isFalse);
    said(app).clear();
    await tapText(t, 'AC not cooling', then: 3);
    expect(said(app), isEmpty);

    // On again: the last message is read straight away.
    await tapLabel(t, 'Read aloud', then: 0.5);
    expect(app.session.readAloud, isTrue);
    expect(said(app), hasLength(1));
  });

  appTest('a message is read again with a tap on it', (t) async {
    final app = await launch(t, as: As.client, at: '/home');
    await tapText(t, 'AC not cooling', then: 3);
    said(app).clear();

    await tapText(t, 'Sounds like', then: 0.5);

    expect(said(app).single, startsWith('Sounds like'));
  });

  appTest('the steps of signing up say what to do', (t) async {
    final app = await launch(t, as: As.guestClient, at: '/home');
    await tapText(t, 'AC not cooling', then: 3);
    await tapText(t, 'Book Emeka', exact: true, then: 1.5);

    expect(said(app).last, endsWith('Type your number at the bottom.'));
    // A number too short is said aloud too.
    await typeAndSend(t, '80312');
    await tapLabel(t, 'Send code', then: 1);
    expect(said(app).last, startsWith('Enter an 11-digit number'));
  });

  appTest('someone who says they want work goes the artisan way', (t) async {
    final app = await launch(t, as: As.firstOpen);

    await typeAndSend(t, "I'm an electrician looking for work");

    expect(find.textContaining('Got it: Electrical.'), findsOneWidget);
    expect(find.text('Join free'), findsOneWidget);
    expect(find.text('Best match'), findsNothing);
    await tapText(t, 'Join free', then: 2);
    expect(app.session.role, UserRole.artisan);
    expect(app.session.guestTrades, ['electrical']);
  });

  appTest('wanting work without a trade asks for the trade', (t) async {
    await launch(t, as: As.firstOpen);

    await typeAndSend(t, 'I need work');

    expect(find.textContaining("What's your trade?"), findsOneWidget);
    await tapText(t, 'Plumbing', then: 0.5);
    expect(find.text('Show me jobs'), findsOneWidget);
  });

  test('prices, numbers and the name sound right', () {
    expect(spoken("In Abuja that's usually ₦8,000 – ₦12,000."),
        "In Abuja that's usually 8,000 to 12,000 naira.");
    expect(spoken('From ₦10,000'), 'From 10,000 naira');
    expect(spoken('I sent a 6-digit code to +234 803 123 4567. Type it here.'),
        'I sent a 6-digit code to plus 2 3 4, 8 0 3, 1 2 3, 4 5 6 7. Type it here.');
    expect(spoken('Your AC, or ACs'), 'Your A.C., or A.C.s');
    expect(spoken('Welcome to Employi'), 'Welcome to Employee');
    expect(spoken('3 jobs were posted'), '3 jobs were posted');
  });
}
