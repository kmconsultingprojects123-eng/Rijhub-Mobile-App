// The client side: finding artisans, bookings, quotes, messages and the
// Profile tab, as a signed-in client unless a test says otherwise.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/models/models.dart';

import 'support/app_harness.dart';

void main() {
  group('home', () {
    appTest('leads with the question, then top-rated artisans and the map',
        (t) async {
      await launch(t, as: As.client, at: '/home');

      expect(find.text('What needs fixing?'), findsOneWidget);
      expect(find.textContaining('Emeka arrives'), findsOneWidget);
      expect(find.text('3 quotes for your job'), findsOneWidget);
      expect(find.text('Top-rated near you'), findsOneWidget);
      expect(find.textContaining('free within 3 km'), findsOneWidget);
    });

    appTest('guests see the same, with a way to sign in', (t) async {
      await launch(t, as: As.guestClient, at: '/home');

      expect(find.text('What needs fixing?'), findsOneWidget);
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('area', () {
    appTest('"Use my location" picks the nearest area', (t) async {
      final app = await launch(t, as: As.guestClient, at: '/explore');

      await tapText(t, 'Abuja', exact: true, then: 1);
      await tapText(t, 'Use my location', exact: true, then: 1.5);

      expect(app.session.area, 'Gwarinpa');
      expect(find.text('Gwarinpa'), findsWidgets);
    });
  });

  group('explore', () {
    appTest('narrows to who is free now, and sorts', (t) async {
      await launch(t, as: As.client, at: '/explore');
      expect(find.textContaining('25 artisans'), findsOneWidget);

      await tapText(t, 'Free now', exact: true);
      expect(find.textContaining('25 artisans'), findsNothing);

      await tapText(t, 'Sort', exact: true, then: 1);
      await tapText(t, 'Nearest', exact: true);
      expect(find.text('Nearest'), findsOneWidget);
    });

    appTest('one trade at a time', (t) async {
      await launch(t, as: As.client, at: '/explore');

      await tapText(t, 'Plumbing', exact: true);

      expect(find.textContaining('plumbers'), findsOneWidget);
      expect(find.text('Kelechi Obi'), findsOneWidget);
      expect(find.text('Emeka Nwosu'), findsNothing);
    });

    appTest('shows the same people on a map', (t) async {
      await launch(t, as: As.client, at: '/explore');

      await tapLabel(t, 'Show on a map');

      expect(find.text('Tap a face to see who it is'), findsOneWidget);
    });

    appTest('a search with no one to show offers to ask Employi instead',
        (t) async {
      await launch(t, as: As.client, at: '/explore');

      await t.enterText(find.byType(TextField).first, 'zzzz');
      await wait(t, 1.5);

      expect(find.text('No one matches that'), findsOneWidget);
      await tapText(t, 'Ask Employi', exact: true, then: 3);
      expect(find.text('zzzz'), findsOneWidget);
    });
  });

  group('artisan profile', () {
    appTest('shows prices, work and reviews, and books', (t) async {
      await launch(t, as: As.client, at: '/artisan/a_emeka');

      expect(find.text('Emeka Nwosu'), findsOneWidget);
      expect(find.text('Services and prices'), findsOneWidget);
      expect(find.text('ID checked'), findsOneWidget);

      await tapText(t, 'Book Emeka', exact: true, then: 2);
      expect(find.textContaining("Let's book Emeka"), findsOneWidget);
    });

    appTest('saving asks guests to sign in first', (t) async {
      await launch(t, as: As.guestClient, at: '/artisan/a_emeka');

      await tapLabel(t, 'Save', then: 1);

      expect(find.textContaining('phone number'), findsWidgets);
    });
  });

  group('bookings', () {
    appTest('upcoming lists jobs waiting on quotes, then booked work',
        (t) async {
      await launch(t, as: As.client, at: '/bookings');

      expect(find.text('Your jobs'), findsOneWidget);
      expect(find.text('Paint the sitting room'), findsOneWidget);
      expect(find.text('3 quotes to compare'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget);
      expect(find.text('AC servicing'), findsOneWidget);
    });

    appTest('a booking says where it stands in one line', (t) async {
      await launch(t, as: As.client, at: '/booking/b_1');

      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.textContaining('Emeka comes'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Start code 4 8 2 9')), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    appTest('cancelling asks why and says what happens to the money',
        (t) async {
      await launch(t, as: As.client, at: '/booking/b_1');

      await tapText(t, 'Cancel', exact: true, then: 1);
      expect(find.text('Cancel this booking?'), findsOneWidget);
      expect(find.textContaining('full payment back'), findsOneWidget);

      await tapText(t, 'My plans changed', exact: true, then: 0.5);
      await tapText(t, 'Cancel booking', exact: true, then: 2);

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('You cancelled: my plans changed'),
          findsOneWidget);
    });

    appTest('rescheduling moves the time', (t) async {
      await launch(t, as: As.client, at: '/booking/b_1');

      await tapText(t, 'Reschedule', exact: true, then: 1);
      await t.tap(find.byType(PromptChip).first);
      await wait(t, 2);

      expect(find.textContaining('Moved to'), findsOneWidget);
    });
  });

  group('quotes', () {
    appTest('comparing quotes and accepting one books and pays', (t) async {
      await launch(t, as: As.client, at: '/jobs/j_c1');
      expect(find.text('3 quotes to compare'), findsOneWidget);

      await tapText(t, 'Accept', exact: true, then: 1);
      // A time (the price comes picked), then pay.
      final time = find.byWidgetPredicate((w) =>
          w is PromptChip && w.label.contains('–') && !w.label.startsWith('₦'));
      await t.ensureVisible(time.first);
      await t.tap(time.first);
      await wait(t, 0.5);
      await tapText(t, 'Pay ₦', then: 1);
      // Paying takes a moment, then the booking opens.
      await tapText(t, 'Pay ₦', then: 3.5);

      expect(find.textContaining('Payment held safely'), findsOneWidget);
      // A quote is the artisan's offer, so accepting it confirms the booking.
      expect(find.textContaining('Bola comes'), findsOneWidget);
    });

    appTest('a posted job can be changed, keeping its quotes', (t) async {
      await launch(t, as: As.client, at: '/jobs/j_c1');

      await tapLabel(t, 'Edit job', then: 1.5);
      expect(find.text('Edit job'), findsOneWidget);
      await t.enterText(
          find.byType(TextField).first, 'Paint the sitting room and hallway');
      await tapText(t, 'Save changes', exact: true, then: 2);

      expect(find.text('Paint the sitting room and hallway'), findsOneWidget);
      expect(find.text('3 quotes to compare'), findsOneWidget);
    });

    appTest('posting a job needs only a few words', (t) async {
      await launch(t, as: As.client, at: '/post-job');

      await t.enterText(
          find.byType(TextField).first, 'Fix my leaking kitchen tap');
      await wait(t, 1.5);
      expect(pickedChips, findsOneWidget);

      await tapText(t, 'Post job', exact: true, then: 3);
      expect(find.textContaining('Fix my leaking kitchen tap'), findsWidgets);
      expect(find.text('Post a job'), findsNothing);
    });
  });

  group('messages', () {
    appTest('a conversation, and a reply', (t) async {
      await launch(t, as: As.client, at: '/messages');

      expect(find.text('Employi'), findsOneWidget);
      await tapText(t, 'Emeka Nwosu', exact: true, then: 2);
      expect(find.textContaining("I'll be there on time"), findsOneWidget);

      await t.enterText(find.byType(TextField).last, 'See you then');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await wait(t, 1.5);
      expect(find.text('See you then'), findsOneWidget);
    });

    appTest('notifications filter by kind', (t) async {
      await launch(t, as: As.client, at: '/notifications');
      expect(find.text('Booking confirmed'), findsOneWidget);

      await tapText(t, 'Quotes', exact: true);

      expect(find.text('Booking confirmed'), findsNothing);
      expect(find.textContaining('New quote'), findsOneWidget);
    });
  });

  group('profile tab', () {
    appTest('keeps to the essentials', (t) async {
      await launch(t, as: As.client, at: '/account');

      for (final row in [
        'Saved artisans',
        'Places',
        'Payments and receipts',
        'Work as an artisan',
        'Help and support',
        'Settings',
        'Sign out'
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('Delete account'), findsNothing);
    });

    appTest('signing out leaves you looking around as a guest', (t) async {
      final app = await launch(t, as: As.client, at: '/account');

      await tapText(t, 'Sign out', exact: true, then: 1);
      await tapText(t, 'Sign out', exact: true, then: 2);

      expect(app.session.isGuest, isTrue);
      expect(find.text('What needs fixing?'), findsOneWidget);
    });

    appTest('one account can work as an artisan too', (t) async {
      final app = await launch(t, as: As.client, at: '/account');

      await tapText(t, 'Work as an artisan', exact: true, then: 1);
      await tapText(t, 'Painting', exact: true, then: 0.3);
      await tapText(t, 'Continue', exact: true, then: 2.5);

      expect(app.session.role, UserRole.artisan);
      expect(find.text('Schedule'), findsOneWidget);
    });

    appTest('settings: appearance in one tap', (t) async {
      final app = await launch(t, as: As.client, at: '/account/settings');

      await tapText(t, 'Dark', exact: true, then: 1);

      expect(app.session.themeMode, ThemeMode.dark);
      expect(find.text('Delete account'), findsOneWidget);
    });

    appTest('help: answers by search, and every way to reach a person',
        (t) async {
      await launch(t, as: As.client, at: '/support');

      for (final way in [
        'Talk to Employi',
        'Chat with us',
        'Call us',
        'WhatsApp',
        'Email'
      ]) {
        expect(find.text(way), findsOneWidget, reason: way);
      }
      await t.enterText(find.byType(TextField).first, 'refund');
      await wait(t, 1);
      expect(find.textContaining('refund'), findsWidgets);
    });

    appTest('payments show what Employi is holding', (t) async {
      await launch(t, as: As.client, at: '/account/payments');

      expect(find.text('Held safely now'), findsOneWidget);
      expect(find.text('Held'), findsOneWidget);
    });
  });

  appTest('a new client with no places opens on adding one', (t) async {
    final app = await launch(t, as: As.guestClient);
    // The mock's network delays only pass while the test pumps.
    final created = app.deps.auth.createAccount(
        phone: '+2348090000002',
        role: UserRole.client,
        firstName: 'Ada',
        lastName: 'Obi');
    await wait(t, 1);
    final signedIn = app.session.signIn(await created);
    await wait(t, 1);
    await signedIn;
    await go(t, '/account/places', then: 3);

    expect(find.text('Add a place'), findsWidgets);
    expect(find.text('Save place'), findsOneWidget);
  });
}
