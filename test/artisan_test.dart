// The artisan side: requests, the job from "on my way" to done, quotes,
// money, and the business pages, as the sample artisan (Emeka) unless a
// test says otherwise.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/models/models.dart';

import 'support/app_harness.dart';

/// Types [code] into the start-code sheet.
Future<void> enterStartCode(WidgetTester t, String code) async {
  await t.enterText(
      find
          .descendant(
              of: find.byType(OtpCodeField),
              matching: find.byType(EditableText))
          .first,
      code);
  await wait(t, 2);
}

void main() {
  group('home', () {
    appTest('shows the next job, then requests to answer', (t) async {
      await launch(t, as: As.artisan, at: '/home');

      expect(find.text('Emeka Nwosu'), findsWidgets);
      expect(find.textContaining('Available'), findsWidgets);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Ngozi A.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
    });

    appTest('one switch takes you off and back', (t) async {
      await launch(t, as: As.artisan, at: '/home');

      await tapLabel(t, 'Available for bookings', then: 1.5);
      expect(find.textContaining('Off'), findsWidgets);

      await tapLabel(t, 'Available for bookings', then: 1.5);
      expect(find.textContaining('Available'), findsWidgets);
    });

    appTest('guests see the jobs and a free way in', (t) async {
      await launch(t, as: As.guestArtisan, at: '/home');

      expect(find.text('Jobs near you'), findsOneWidget);
      expect(find.textContaining('open this week'), findsOneWidget);
    });
  });

  group('requests', () {
    appTest('accepting a request from home books it', (t) async {
      await launch(t, as: As.artisan, at: '/home');

      await tapText(t, 'Accept', exact: true, then: 2.5);

      // Booked, and opened, with the client told.
      expect(find.textContaining('Ngozi has been told'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
    });

    appTest('declining asks why, so the client hears something kind',
        (t) async {
      await launch(t, as: As.artisan, at: '/requests/r_1');
      expect(
          find.text(
              'Two sockets in my kitchen are sparking. I\'ve switched them off at the board for now.'),
          findsOneWidget);

      await tapText(t, 'Decline', exact: true, then: 1);
      expect(find.byType(PromptChip), findsWidgets);
      await t.tap(find.byType(PromptChip).first);
      await wait(t, 0.5);
      await tapText(t, 'Decline', exact: true, then: 2);

      expect(find.textContaining('Declined'), findsWidgets);
    });
  });

  group('a booking, start to finish', () {
    appTest('on my way, start with the client\'s code, mark done', (t) async {
      await launch(t, as: As.artisan, at: '/booking/b_1');
      expect(find.text('Confirmed'), findsOneWidget);

      await tapText(t, "I'm on my way", exact: true, then: 2);
      expect(find.text('On your way'), findsOneWidget);

      await tapText(t, 'Start the job', exact: true, then: 1);
      await enterStartCode(t, '4829');
      expect(find.text('Working'), findsOneWidget);

      await tapText(t, 'Mark as done', exact: true, then: 1);
      await tapText(t, 'Yes, mark as done', exact: true, then: 2);
      expect(find.text('Waiting for Chidinma'), findsOneWidget);
    });

    appTest('a wrong start code doesn\'t start the job', (t) async {
      await launch(t, as: As.artisan, at: '/booking/b_1');
      await tapText(t, "I'm on my way", exact: true, then: 2);

      await tapText(t, 'Start the job', exact: true, then: 1);
      await enterStartCode(t, '1111');

      expect(find.textContaining("That code doesn't match"), findsOneWidget);
      expect(find.text('On your way'), findsOneWidget);
    });

    appTest('then the client confirms, which pays the artisan, and reviews',
        (t) async {
      final app = await launch(t, as: As.artisan, at: '/booking/b_1');
      await tapText(t, "I'm on my way", exact: true, then: 2);
      await tapText(t, 'Start the job', exact: true, then: 1);
      await enterStartCode(t, '4829');
      await tapText(t, 'Mark as done', exact: true, then: 1);
      await tapText(t, 'Yes, mark as done', exact: true, then: 2);

      // The same booking, from the client's side.
      await app.session.signIn(MockData.sampleUser(UserRole.client));
      await go(t, '/home');
      await go(t, '/booking/b_1');
      expect(find.text('Is it done?'), findsOneWidget);

      await tapText(t, "Confirm it's done", exact: true, then: 1);
      await tapText(t, 'Yes, release payment', exact: true, then: 2);
      expect(find.text('Post review'), findsOneWidget);

      // Five stars to start with; a tap posts it.
      await tapText(t, 'Post review', exact: true, then: 2);
      expect(find.textContaining('Thanks! Your review helps others choose.'),
          findsOneWidget);
    });
  });

  group('jobs and quotes', () {
    appTest('the board starts with your trades', (t) async {
      await launch(t, as: As.artisan, at: '/explore');

      expect(find.text('My trades'), findsOneWidget);
      expect(find.textContaining('open this week'), findsOneWidget);
      expect(find.text('AC not cooling and leaking water'), findsOneWidget);
    });

    appTest('a quote: a price, a time, a word, sent', (t) async {
      await launch(t, as: As.artisan, at: '/job/j_1');

      await tapText(t, 'Send a quote', exact: true, then: 1.5);
      await t.enterText(find.byType(TextField).first, '10000');
      await wait(t, 0.5);
      await tapText(t, 'Send quote · ₦10,000', exact: true, then: 2);

      expect(find.textContaining('Quote sent'), findsOneWidget);
    });

    appTest('after a first quote, notifications are offered, once', (t) async {
      final app =
          await launch(t, as: As.artisan, at: '/job/j_1', pushAllowed: false);

      await tapText(t, 'Send a quote', exact: true, then: 1.5);
      await t.enterText(find.byType(TextField).first, '10000');
      await wait(t, 0.5);
      await tapText(t, 'Send quote · ₦10,000', exact: true, then: 2);
      expect(find.text('Know when the client picks you?'), findsOneWidget);

      await tapText(t, 'Turn on notifications', exact: true, then: 1.5);
      expect(find.textContaining('Quote sent'), findsOneWidget);
      expect(app.session.pushAsked, isTrue);
    });

    appTest('your quotes are one tab over', (t) async {
      await launch(t, as: As.artisan, at: '/explore');

      await tapText(t, 'Your quotes', exact: true, then: 1.5);

      expect(find.text('Service two split AC units'), findsOneWidget);
    });
  });

  group('money', () {
    appTest('the wallet shows what can be withdrawn and where it goes',
        (t) async {
      await launch(t, as: As.artisan, at: '/account/wallet');

      expect(find.text('Ready to withdraw'), findsOneWidget);
      expect(find.text('On hold'), findsOneWidget);
      expect(find.textContaining('GTBank'), findsWidgets);
    });

    appTest('withdrawing everything in two taps', (t) async {
      await launch(t, as: As.artisan, at: '/account/wallet/withdraw');

      await tapText(t, 'All ·', then: 0.5);
      await tapText(t, 'Withdraw ₦', then: 2.5);

      expect(find.textContaining('on its way'), findsWidgets);
    });

    appTest('a bank account fills in its own name', (t) async {
      await launch(t, as: As.artisan, at: '/account/wallet/bank');

      await t.enterText(find.byType(TextField).last, '0123456789');
      await wait(t, 2);

      expect(find.text('EMEKA NWOSU'), findsOneWidget);
    });
  });

  group('your business', () {
    appTest('the profile tab keeps to the essentials', (t) async {
      await launch(t, as: As.artisan, at: '/account');

      for (final row in const [
        'See your profile as clients do',
        'Services and prices',
        'Work photos',
        'Work area',
        'Working hours',
        'Reviews',
        'Wallet and payouts',
        'Hire for yourself',
        'Help and support',
        'Settings',
        'Sign out',
      ]) {
        await t.scrollUntilVisible(find.text(row), 120,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(row), findsOneWidget, reason: row);
      }
      // Verified, so nothing to nag about.
      expect(find.text('Get verified'), findsNothing);
    });

    appTest('adding a service with its price', (t) async {
      await launch(t, as: As.artisan, at: '/account/services');

      await tapText(t, 'Add a service', exact: true, then: 1);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), 'Fridge gas refill');
      await t.enterText(fields.at(1), '15000');
      await wait(t, 0.5);
      await tapText(t, 'Save', exact: true, then: 2);

      expect(find.text('Fridge gas refill'), findsOneWidget);
    });

    appTest('working hours: one tap for the usual week', (t) async {
      await launch(t, as: As.artisan, at: '/account/hours');

      await tapText(t, 'Mon–Fri, 9–5', exact: true, then: 0.5);
      expect(find.text('Mon–Fri, 9 AM–5 PM'), findsOneWidget);

      await tapText(t, 'Save', exact: true, then: 2);
      expect(find.textContaining('Hours saved'), findsOneWidget);
    });

    appTest('the ID check: NIN, then a selfie', (t) async {
      await launch(t, as: As.guestArtisan, at: '/account/verification');

      await tapText(t, 'Start', exact: true, then: 1);
      await t.enterText(find.byType(TextField).first, '12345678901');
      await wait(t, 0.5);
      await tapText(t, 'Continue', exact: true, then: 1);
      await tapText(t, 'Take selfie', exact: true, then: 1.5);
      await tapText(t, 'Send for checking', exact: true, then: 3);

      expect(find.text("We're checking your ID"), findsOneWidget);
    });

    appTest('your profile as clients see it', (t) async {
      await launch(t, as: As.artisan, at: '/account/profile');

      expect(find.text('This is how clients see you'), findsOneWidget);
      expect(find.text('Services and prices'), findsOneWidget);
      expect(find.textContaining('Book Emeka'), findsNothing);
    });
  });
}
