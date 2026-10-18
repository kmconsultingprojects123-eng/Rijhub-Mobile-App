// The first open: a conversation with RijHub, with three ways in: say
// what's wrong, "I'm an artisan", or "Look around".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/data/models/models.dart';

import 'support/app_harness.dart';

void main() {
  appTest('a first open starts with RijHub, not a form', (t) async {
    final app = await launch(t, as: As.firstOpen);

    expect(find.textContaining('ID-checked artisans'), findsOneWidget);
    expect(find.textContaining("Hi! I'm RijHub"), findsOneWidget);
    expect(find.text("I'm an artisan"), findsOneWidget);
    expect(find.text('Look around'), findsOneWidget);
    // Nowhere to go back to yet.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(app.session.hasOnboarded, isFalse);
  });

  appTest('"Look around" goes home as a guest, once', (t) async {
    final app = await launch(t, as: As.firstOpen);

    await tapText(t, 'Look around');

    expect(find.text('What needs fixing?'), findsOneWidget);
    expect(app.session.hasOnboarded, isTrue);
    expect(app.session.isGuest, isTrue);
    expect(app.session.role, UserRole.client);
  });

  appTest('saying what is wrong finds artisans, and counts as getting in',
      (t) async {
    final app = await launch(t, as: As.firstOpen);

    await tapText(t, 'AC not cooling', then: 3);

    expect(find.text('Best match'), findsOneWidget);
    expect(find.text('Book Emeka'), findsOneWidget);
    expect(app.session.hasOnboarded, isTrue);
    // The welcome's ways in are gone, and back now leads home.
    expect(find.text('Look around'), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  appTest('an artisan picks trades, sees this week\'s jobs, and lands on them',
      (t) async {
    final app = await launch(t, as: As.firstOpen);

    await tapText(t, "I'm an artisan", then: 2);
    expect(find.textContaining("What's your trade?"), findsOneWidget);
    // No jobs button until a trade is picked.
    expect(find.text('Show me jobs'), findsNothing);

    await tapText(t, 'AC repair', then: 0.5);
    await tapText(t, 'Generator', then: 0.5);
    expect(pickedChips, findsNWidgets(2));

    await tapText(t, 'Show me jobs', then: 3);
    expect(find.textContaining('this week'), findsWidgets);
    expect(find.textContaining('Free to join'), findsOneWidget);

    await tapText(t, 'See all', then: 3);
    expect(find.text('Jobs'), findsWidgets);
    expect(find.text('My trades'), findsOneWidget);
    expect(app.session.role, UserRole.artisan);
    expect(app.session.guestTrades, ['ac', 'generator']);
  });

  appTest('three trades at most', (t) async {
    await launch(t, as: As.firstOpen);
    await tapText(t, "I'm an artisan", then: 2);

    for (final trade in ['AC repair', 'Electrical', 'Plumbing', 'Generator']) {
      await tapText(t, trade, then: 0.3);
    }

    expect(pickedChips, findsNWidgets(3));
  });

  appTest('the rarer trades are one tap away', (t) async {
    await launch(t, as: As.firstOpen);
    await tapText(t, "I'm an artisan", then: 2);
    expect(find.text('TV & decoder'), findsNothing);

    await tapText(t, 'More trades', then: 0.5);

    expect(find.text('TV & decoder'), findsOneWidget);
  });

  appTest('later opens go straight home', (t) async {
    await launch(t, as: As.guestClient);

    expect(find.text('What needs fixing?'), findsOneWidget);
    expect(find.textContaining('ID-checked artisans'), findsNothing);
  });

  appTest('typing a problem in the welcome works like a chip', (t) async {
    final app = await launch(t, as: As.firstOpen);

    await t.enterText(
        find.byType(TextField).last, 'my generator will not start');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 3);

    expect(find.text('my generator will not start'), findsOneWidget);
    expect(find.text('Best match'), findsOneWidget);
    expect(app.session.hasOnboarded, isTrue);
  });
}
