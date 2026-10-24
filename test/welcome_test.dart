// The first open: a conversation with RijHub, with three ways in: say
// what's wrong, "I'm an artisan", or "Look around".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';

import 'support/app_harness.dart';

void main() {
  appTest('a first open starts with Employi, not a form', (t) async {
    final app = await launch(t, as: As.firstOpen);

    expect(find.textContaining('ID-checked artisans'), findsOneWidget);
    expect(find.textContaining("Hi! I'm Employi"), findsOneWidget);
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

  appTest('an artisan picks trades, sees the jobs, and joins in the chat',
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
    expect(find.textContaining('Joining is free'), findsOneWidget);

    // Joining is the number, its code and a name, all in the chat.
    await tapText(t, 'Join free', exact: true, then: 1.5);
    expect(find.textContaining("What's your phone number?"), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '8091234599');
    await tapLabel(t, 'Send code', then: 2);
    await t.enterText(
        find
            .descendant(
                of: find.byType(OtpCodeField),
                matching: find.byType(EditableText))
            .first,
        '123456');
    await wait(t, 2.5);
    // The trades are known, so there's no form: just the name.
    expect(find.textContaining('as it is on your ID'), findsOneWidget);
    expect(find.text('What do you do?'), findsNothing);

    await t.enterText(find.byType(TextField).last, 'Emeka Nwosu');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 4);
    expect(app.session.isSignedIn, isTrue);
    expect(app.session.role, UserRole.artisan);
    expect(app.session.user!.tradeIds, ['ac', 'generator']);
    // His home leads with what's left before clients can book him.
    expect(find.text('Emeka Nwosu'), findsOneWidget);
    expect(find.text('Get ready for clients'), findsOneWidget);
  });

  appTest('an artisan can look at the jobs first, as a guest', (t) async {
    final app = await launch(t, as: As.firstOpen);
    await tapText(t, "I'm an artisan", then: 2);
    await tapText(t, 'AC repair', then: 0.5);
    await tapText(t, 'Show me jobs', then: 3);

    await tapText(t, 'first', then: 3);
    expect(find.text('My trades'), findsOneWidget);
    expect(app.session.role, UserRole.artisan);
    expect(app.session.isGuest, isTrue);
    expect(app.session.guestTrades, ['ac']);
  });

  appTest('an artisan can type the trade, and it is picked for them',
      (t) async {
    await launch(t, as: As.firstOpen);
    await tapText(t, "I'm an artisan", then: 2);

    await t.enterText(find.byType(TextField).last, 'I fix ACs and fridges');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 3);
    expect(find.textContaining('Got it: AC repair.'), findsOneWidget);
    expect(find.textContaining('this week'), findsWidgets);
    expect(find.text('Join free'), findsOneWidget);
  });

  appTest('a trade that isn\'t matched keeps the list to pick from', (t) async {
    await launch(t, as: As.firstOpen);
    await tapText(t, "I'm an artisan", then: 2);

    await t.enterText(find.byType(TextField).last, 'I sell things');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await wait(t, 2);
    expect(find.textContaining('Pick the closest'), findsOneWidget);
    expect(find.text('Join free'), findsNothing);
    await tapText(t, 'AC repair', then: 0.5);
    expect(find.text('Show me jobs'), findsOneWidget);
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

  appTest('before any artisan is ID-checked, the welcome skips the count',
      (t) async {
    await launch(t, as: As.firstOpen, catalog: _City(artisans: 0));

    expect(find.textContaining('ID-checked artisan'), findsNothing);
    expect(find.textContaining("Hi! I'm Employi"), findsOneWidget);
  });

  appTest('one artisan, not yet rated, is counted without a rating', (t) async {
    await launch(t, as: As.firstOpen, catalog: _City(artisans: 1));

    expect(find.text('1 ID-checked artisan'), findsOneWidget);
    expect(find.text('across Abuja'), findsOneWidget);
    expect(find.textContaining('average rating'), findsNothing);
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

/// The sample city with [artisans] ID-checked artisans, none rated yet.
class _City extends MockCatalogRepository {
  _City({required this.artisans});

  final int artisans;

  @override
  Future<MarketStats> stats() async =>
      MarketStats(verifiedArtisans: artisans, averageRating: 0);
}
