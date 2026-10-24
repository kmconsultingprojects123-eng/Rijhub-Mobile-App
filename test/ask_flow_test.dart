// Booking through the Ask conversation: say what's wrong, pick who, when
// and where, confirm and pay; or send the job out for quotes. Guests sign up
// inside the conversation as soon as they choose who to book.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/features/ask/ask_flow.dart';
import 'package:rijhub/features/location/area_picker_sheet.dart';

import 'support/app_harness.dart';

/// The first of the quick replies, whatever the time of day makes them.
Future<void> tapFirstReply(WidgetTester t) async {
  await t.tap(find.byType(PromptChip).first);
  await wait(t, 1.5);
}

/// A guest's sign-up, in the chat: the number, its code, the full name.
Future<void> signUpInChat(WidgetTester t,
    {String phone = '8091234567', String name = 'Ada Obi'}) async {
  await t.enterText(find.byType(TextField).last, phone);
  await tapLabel(t, 'Send code', then: 2);
  await t.enterText(
      find
          .descendant(
              of: find.byType(OtpCodeField),
              matching: find.byType(EditableText))
          .first,
      '123456');
  await wait(t, 2.5);
  await t.enterText(find.byType(TextField).last, name);
  await t.testTextInput.receiveAction(TextInputAction.send);
  await wait(t, 2.5);
}

/// From home: a problem, its best match (a guest signs up there), the first
/// time offered.
Future<void> askAndPickTime(WidgetTester t, {bool guest = false}) async {
  await tapText(t, 'AC not cooling', then: 3);
  await tapText(t, 'Book Emeka', exact: true, then: 1.5);
  if (guest) await signUpInChat(t);
  expect(find.text('When should Emeka come?'), findsOneWidget);
  await tapFirstReply(t);
}

void main() {
  appTest('a client books and pays in one conversation', (t) async {
    await launch(t, as: As.client, at: '/home');

    await askAndPickTime(t);
    expect(find.textContaining('Where should Emeka come?'), findsOneWidget);
    await tapText(t, 'Home ·', then: 2);

    // The booking to check, with the total, before anything is sent.
    expect(find.text("Here's your booking:"), findsOneWidget);
    expect(find.textContaining('Confirm ·'), findsOneWidget);

    await tapText(t, 'Confirm ·', then: 1);
    expect(find.text('Card'), findsOneWidget);
    await tapText(t, 'Pay ₦', then: 3);

    expect(find.textContaining('Done! I sent your request to Emeka'),
        findsOneWidget);
    expect(find.textContaining('Start code'), findsOneWidget);
    expect(find.text('View booking'), findsOneWidget);
  });

  appTest('after a first booking, notifications are offered, once', (t) async {
    final app = await launch(t, as: As.client, at: '/home', pushAllowed: false);
    await askAndPickTime(t);
    await tapText(t, 'Home ·', then: 2);
    await tapText(t, 'Confirm ·', then: 1);
    await tapText(t, 'Pay ₦', then: 3);

    expect(find.text('Want a ping when Emeka replies?'), findsOneWidget);
    expect(find.text('View booking'), findsOneWidget);
    await tapText(t, 'Turn on notifications', exact: true, then: 1.5);

    expect(find.textContaining("Done. I'll ping you"), findsOneWidget);
    expect(app.session.pushAsked, isTrue);
  });

  appTest('backing out of payment sends nothing', (t) async {
    await launch(t, as: As.client, at: '/home');
    await askAndPickTime(t);
    await tapText(t, 'Home ·', then: 2);
    await tapText(t, 'Confirm ·', then: 1);

    // Close the payment sheet without paying.
    await t.tapAt(const Offset(195, 120));
    await wait(t, 1.5);

    expect(find.textContaining("Your booking isn't sent until you pay"),
        findsOneWidget);
    expect(find.textContaining('Done!'), findsNothing);
  });

  appTest('an address that names no area is asked for it once', (t) async {
    await launch(t, as: As.guestClient, at: '/home');

    await askAndPickTime(t, guest: true);
    await tapText(t, 'Type the address', then: 1);
    await t.enterText(find.byType(TextField).last, 'Behind the big mosque');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 2);

    expect(find.text('Which area of Abuja is that in?'), findsOneWidget);
    // The list of areas is already open.
    expect(find.byType(AreaPickerSheet), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Jabi');
    await wait(t, 1);
    await tapText(t, 'Jabi', exact: true, then: 2);

    expect(find.text("Here's your booking:"), findsOneWidget);
    expect(find.textContaining('Confirm ·'), findsOneWidget);
  });

  appTest('a guest chooses who to book, signs up in the chat, and books on',
      (t) async {
    final app = await launch(t, as: As.guestClient, at: '/home');

    await tapText(t, 'AC not cooling', then: 3);
    await tapText(t, 'Book Emeka', exact: true, then: 1.5);
    // Straight to signing up, in the chat: no sheet, no form.
    expect(find.textContaining("Let's book Emeka. What's your phone number?"),
        findsOneWidget);
    expect(find.textContaining('By continuing you agree'), findsOneWidget);

    await t.enterText(find.byType(TextField).last, '8091234567');
    await tapLabel(t, 'Send code', then: 2);
    expect(find.textContaining('I sent a 6-digit code'), findsOneWidget);
    await t.enterText(
        find
            .descendant(
                of: find.byType(OtpCodeField),
                matching: find.byType(EditableText))
            .first,
        '123456');
    await wait(t, 2.5);
    expect(find.textContaining('as it is on your ID'), findsOneWidget);

    // One name isn't the name on an ID.
    await t.enterText(find.byType(TextField).last, 'Ada');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 1);
    expect(find.text('Add your surname too, as it is on your ID.'),
        findsOneWidget);
    expect(app.session.isGuest, isTrue);

    await t.enterText(find.byType(TextField).last, 'Ada Obi');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 2.5);
    expect(app.session.isSignedIn, isTrue);
    expect(app.session.user!.firstName, 'Ada');
    expect(find.textContaining('Your account is ready'), findsOneWidget);

    // Then on with the booking, and paying asks for nothing more.
    expect(find.text('When should Emeka come?'), findsOneWidget);
    await tapFirstReply(t);
    await tapText(t, 'Type the address', then: 1);
    await t.enterText(
        find.byType(TextField).last, 'Plot 12, Aminu Kano Crescent, Wuse 2');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 2);
    // The address named its area, so nobody asks for it.
    expect(find.textContaining('Which area'), findsNothing);
    await tapText(t, 'Confirm ·', then: 1.5);
    expect(find.textContaining("What's your phone number?"), findsNothing);
    expect(find.text('Card'), findsOneWidget);
    await tapText(t, 'Pay ₦', then: 3);
    expect(find.textContaining('Done! I sent your request to Emeka'),
        findsOneWidget);
  });

  appTest('a wrong code says so, and the number can be changed', (t) async {
    await launch(t, as: As.guestClient, at: '/home');
    await tapText(t, 'Leaking pipe', then: 3);
    await tapText(t, 'Get quotes', then: 1.5);

    await t.enterText(find.byType(TextField).last, '8091234567');
    await tapLabel(t, 'Send code', then: 2);
    await t.enterText(
        find
            .descendant(
                of: find.byType(OtpCodeField),
                matching: find.byType(EditableText))
            .first,
        '000000');
    await wait(t, 2.5);
    expect(find.textContaining("That code isn't right"), findsOneWidget);

    await tapText(t, 'Change number', then: 1);
    expect(find.textContaining("What's the right number?"), findsOneWidget);
  });

  appTest('getting quotes sends the job out and lists it under Bookings',
      (t) async {
    await launch(t, as: As.client, at: '/home');

    await tapText(t, 'Leaking pipe', then: 3);
    await tapText(t, 'Get quotes from all', then: 3);

    expect(find.textContaining('Quotes usually come in within 30 minutes'),
        findsOneWidget);
    expect(find.textContaining('Sent to'), findsOneWidget);

    await go(t, '/bookings');
    expect(find.text('Your jobs'), findsOneWidget);
    expect(find.text('Waiting for quotes'), findsWidgets);
  });

  appTest('booking from a profile starts from the artisan\'s own services',
      (t) async {
    await launch(t, as: As.client, at: '/book/a_emeka');

    expect(find.textContaining("Let's book Emeka"), findsOneWidget);
    expect(find.text('AC servicing'), findsOneWidget);
    expect(find.text('Something else'), findsOneWidget);

    await tapText(t, 'AC servicing', exact: true, then: 1.5);
    expect(find.text('When should Emeka come?'), findsOneWidget);
  });

  appTest('one booking can cover more than one service', (t) async {
    await launch(t, as: As.client, at: '/book/a_emeka');
    await tapText(t, 'AC servicing', exact: true, then: 1.5);
    await tapFirstReply(t);
    await tapText(t, 'Home ·', then: 2);

    await tapText(t, 'Add a service', exact: true, then: 1);
    await tapText(t, 'Gas top-up ·', then: 1.5);

    expect(find.text('AC servicing + Gas top-up'), findsOneWidget);
    expect(find.text('Gas top-up'), findsOneWidget);
    expect(find.textContaining('Confirm · ₦21'), findsOneWidget);
  });

  appTest('something an artisan doesn\'t list goes to them for a price',
      (t) async {
    await launch(t, as: As.client, at: '/book/a_emeka');

    await tapText(t, 'Something else', exact: true, then: 1.5);
    expect(find.textContaining('Tell me what you need'), findsOneWidget);

    await t.enterText(
        find.byType(TextField).last, 'Move a split AC to another room');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 3);

    expect(find.textContaining('Sent to Emeka'), findsWidgets);
  });

  appTest('a voice note is heard and answered', (t) async {
    await launch(t, as: As.client, at: '/home');

    await tapLabel(t, 'Record a voice note', then: 0.5);
    await tapLabel(t, 'Send voice note', then: 4);

    expect(find.text('Best match'), findsOneWidget);
  });

  appTest('the question stays in view when the keyboard opens', (t) async {
    await launch(t, as: As.guestClient, at: '/home');
    await tapText(t, 'AC not cooling', then: 3);
    await tapText(t, 'Book Emeka', exact: true, then: 1.5);

    t.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await wait(t, 1);

    final chat = t.getRect(find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical));
    final question =
        t.getRect(find.textContaining("What's your phone number?"));
    expect(question.top, greaterThanOrEqualTo(chat.top));
    expect(question.bottom, lessThanOrEqualTo(chat.bottom));
  });

  test('the times offered start at 8 AM, even after midnight', () {
    final labels = [
      for (final (label, _) in suggestedWindows(DateTime(2026, 10, 24, 0, 30)))
        label
    ];
    expect(labels.first, 'Today, 8–10 AM');
    expect(labels, contains('Tomorrow, 9–11 AM'));
    // Late in the day, only tomorrow.
    final late = suggestedWindows(DateTime(2026, 10, 24, 18, 10));
    expect(late.first.$1, startsWith('Tomorrow'));
  });
}
