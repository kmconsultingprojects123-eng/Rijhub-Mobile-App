// The client Home tab in the real app on mock data: what it says, what the
// first screen holds, and that it stays usable with reduced motion, large
// text and screen readers.
//
// The mock repositories wait with Future.delayed, which completes when the
// test pumps fake time past it, so tests pump rather than await them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:rijhub/app/app.dart';
import 'package:rijhub/app/auth_gate.dart';
import 'package:rijhub/app/dependencies.dart';
import 'package:rijhub/app/routes.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/core/widgets/widgets.dart';
import 'package:rijhub/data/mock/mock_data.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/home/widgets/client_artisan_row.dart';
import 'package:rijhub/features/home/widgets/client_booking_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers each request from [answers] in turn, repeating the last one.
/// An [Exception] in the list fails that request.
class _ScriptedArtisans implements ArtisanRepository {
  _ScriptedArtisans(this.answers);

  final List<Object> answers;
  int calls = 0;

  @override
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  }) async {
    final answer = answers[calls < answers.length ? calls : answers.length - 1];
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (answer is Exception) throw answer;
    return answer as List<Artisan>;
  }

  @override
  Future<List<HiredArtisan>> hiredBefore() async => const [];
}

/// Artisans that never arrive, so the list stays loading.
class _LoadingArtisans implements ArtisanRepository {
  @override
  Future<List<Artisan>> topRatedNearby({
    required String area,
    String? categoryId,
    bool freeNow = false,
    int limit = 6,
  }) =>
      Completer<List<Artisan>>().future;

  @override
  Future<List<HiredArtisan>> hiredBefore() async => const [];
}

class _FailingCatalog implements CatalogRepository {
  @override
  Future<List<String>> areas() async => MockData.areas;

  @override
  Future<List<ServiceCategory>> categories() =>
      Future.error(Exception('offline'));

  @override
  Future<List<PriceGuideItem>> priceGuide() =>
      Future.error(Exception('offline'));
}

class _FailingBookings implements BookingRepository {
  @override
  Future<List<Booking>> upcoming({required UserRole as}) =>
      Future.error(Exception('offline'));
}

/// The sample booking, without the number to call about it.
class _NoNumberBookings implements BookingRepository {
  @override
  Future<List<Booking>> upcoming({required UserRole as}) async {
    final sample = MockData.clientBookings(DateTime.now()).first;
    return [
      Booking(
        id: sample.id,
        serviceName: sample.serviceName,
        categoryId: sample.categoryId,
        scheduledAt: sample.scheduledAt,
        status: sample.status,
        counterpartName: sample.counterpartName,
        area: sample.area,
        startCode: sample.startCode,
      ),
    ];
  }
}

/// The app opened on Home and the state behind it.
class _Home {
  _Home(this.session, this.prompts);

  final SessionController session;

  /// What the sign-in gate was asked for. It never signs anyone in.
  final List<AuthPrompt> prompts;
}

/// Opens the app on Home as a guest client, or as the sample client when
/// [signedIn]. [height] makes the phone taller, so all of Home is built.
Future<_Home> _open(
  WidgetTester t, {
  bool signedIn = false,
  double width = 390,
  double height = 1800,
  ArtisanRepository? artisans,
  CatalogRepository? catalog,
  BookingRepository? bookings,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(width * 3, height * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final mock = AppDependencies.mock();
  final deps = AppDependencies(
    auth: mock.auth,
    catalog: catalog ?? mock.catalog,
    artisans: artisans ?? mock.artisans,
    jobs: mock.jobs,
    bookings: bookings ?? mock.bookings,
    artisanDashboard: mock.artisanDashboard,
  );
  final session = SessionController(prefs: prefs, auth: deps.auth);
  if (signedIn) {
    await session.signIn(MockData.sampleUser(UserRole.client));
  } else {
    await session.continueAsGuest(UserRole.client);
  }
  final prompts = <AuthPrompt>[];
  await t.pumpWidget(RijHubApp(
    dependencies: deps,
    session: session,
    authFlow: AuthFlowController(auth: deps.auth, session: session),
    authGate: AuthGate((context, prompt) async {
      prompts.add(prompt);
      return false;
    }),
    initialLocation: Routes.home,
  ));
  await _wait(t);
  return _Home(session, prompts);
}

/// Pumps [total] of fake time in short frames, so timers, mock latencies
/// and animations all run.
Future<void> _wait(
  WidgetTester t, [
  Duration total = const Duration(milliseconds: 1500),
]) async {
  const frame = Duration(milliseconds: 50);
  for (var waited = Duration.zero; waited < total; waited += frame) {
    await t.pump(frame);
  }
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await _wait(t, const Duration(milliseconds: 500));
}

/// Pulls the list down from its top past the refresh threshold, which is a
/// share of the list's height, so on a phone-sized view.
Future<void> _pullToRefresh(WidgetTester t) async {
  final list = t.getRect(find.byType(CustomScrollView));
  await t.flingFrom(
      list.topCenter.translate(0, 60), const Offset(0, 400), 1000);
  await _wait(t, const Duration(milliseconds: 1500));
}

/// The section title row that shows [title].
Finder _header(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SectionHeader));

/// The sample client's booking card, by its start code.
Finder get _herBooking => find.textContaining('Code 4829');

/// Where the tab bar starts on a 390x844 phone with a 34pt home indicator:
/// what is above it is the first screen.
double _fold(WidgetTester t) => t.getRect(find.byType(CustomScrollView)).bottom;

/// Lays text out in Inter, as on a device. The test font's wider glyphs
/// would overflow rows that fit in the real one.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  group('The first screen', () {
    testWidgets('shows a guest five artisans, under a short header', (t) async {
      await _open(t, height: 844);
      final fold = _fold(t);
      // The phone's own bars: 47 above, the tab bar and home indicator below.
      expect(fold, closeTo(844 - 34 - 60, 1));
      final rows = t
          .widgetList(find.byType(ClientArtisanRow))
          .map((row) => t.getRect(find.byWidget(row)))
          .toList();
      final above = rows.where((r) => r.bottom <= fold).length;
      expect(above, 5, reason: 'artisans fill the first screen');
      // Header, search and chips take no more than ~150pt from the top of
      // the safe area (47 here) to the bottom of the chips.
      final chips = t.getRect(
        find
            .descendant(
              of: find.widgetWithText(AppChip, 'Free now'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(chips.bottom - 47, lessThanOrEqualTo(150));
      // Rows are three-line list items, 88pt each, with hairlines that
      // start at the text column (16 + 56 + 16).
      for (final row in rows.take(5)) {
        expect(row.height, closeTo(88, 0.5));
      }
      final name = t.getRect(find.text('Emeka Nwosu'));
      expect(name.left, closeTo(88, 0.5));
      // Chips look 32pt tall, in a row that starts at the gutter.
      expect(chips.height, closeTo(AppChip.height, 0.5));
      expect(chips.left, closeTo(16, 0.5));
      expect(t.takeException(), isNull);
      await _close(t);
    });

    testWidgets('keeps four artisans in view with a booking above them',
        (t) async {
      await _open(t, signedIn: true, height: 844);
      final fold = _fold(t);
      expect(_herBooking, findsOneWidget);
      final card = t.getRect(find.byType(ClientBookingCard));
      // A two-line card: 72pt, not a hero.
      expect(card.height, lessThan(88));
      final rows = t
          .widgetList(find.byType(ClientArtisanRow))
          .map((row) => t.getRect(find.byWidget(row)))
          .where((r) => r.bottom <= fold)
          .length;
      expect(rows, greaterThanOrEqualTo(4));
      await _close(t);
    });

    testWidgets('loads with five rows of skeleton, the same height as rows',
        (t) async {
      await _open(t, artisans: _LoadingArtisans(), height: 844);
      final skeletons = find.byType(ClientArtisanRowSkeleton);
      expect(skeletons, findsNWidgets(5));
      for (final skeleton in t.widgetList(skeletons)) {
        expect(t.getRect(find.byWidget(skeleton)).height, closeTo(88, 0.5));
      }
      // The header and filters work while the list loads.
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(find.widgetWithText(AppChip, 'Free now'), findsOneWidget);
      await _close(t);
    });
  });

  testWidgets('opens with reduced motion, and the booking comes and goes',
      (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final home = await _open(t, signedIn: true);
    expect(t.takeException(), isNull);
    expect(_herBooking, findsOneWidget);

    unawaited(home.session.signOut());
    await _wait(t);
    expect(t.takeException(), isNull);
    expect(_herBooking, findsNothing);
    await _close(t);
  });

  testWidgets('"See all" under Top-rated takes taps just off the row',
      (t) async {
    await _open(t);
    for (final offset in [-8.0, 8.0]) {
      final header = t.getRect(_header('Top-rated in Abuja'));
      final x = t.getCenter(
        find.descendant(
          of: _header('Top-rated in Abuja'),
          matching: find.text('See all'),
        ),
      );
      await t.tapAt(
        Offset(x.dx, offset < 0 ? header.top + offset : header.bottom + offset),
      );
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Coming in the redesign'), findsOneWidget);
      await t.tap(find.byIcon(IconsaxPlusLinear.home_2));
      await _wait(t, const Duration(milliseconds: 600));
    }
    await _close(t);
  });

  testWidgets('the bell has no unread mark while there are no notifications',
      (t) async {
    final semantics = t.ensureSemantics();
    await _open(t, signedIn: true);
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Notifications, ')), findsNothing);
    await t.tap(find.bySemanticsLabel('Notifications'));
    await _wait(t, const Duration(milliseconds: 300));
    expect(
      find.text('Notifications are next in the redesign.'),
      findsOneWidget,
    );
    await _close(t);
    semantics.dispose();
  });

  testWidgets("the header's Sign in welcomes new and returning people alike",
      (t) async {
    final home = await _open(t);
    await t.tap(find.widgetWithText(AppButton, 'Sign in'));
    await t.pump();
    expect(home.prompts, [AuthPrompt.join]);
    await _close(t);
  });

  group('Search', () {
    testWidgets('opens Explore, and voice says it is coming', (t) async {
      await _open(t);
      await t.tap(find.bySemanticsLabel('Search by voice'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(find.text('Voice search is coming soon.'), findsOneWidget);
      expect(find.text('Coming in the redesign'), findsNothing);

      await t.tap(find.bySemanticsLabel('Search. What needs fixing?'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Coming in the redesign'), findsOneWidget);
      expect(
        find.text('Search every service and see artisans on a map.'),
        findsOneWidget,
      );
      await _close(t);
    });
  });

  group('Rows', () {
    testWidgets('each is one stop for a screen reader, in sentences',
        (t) async {
      final semantics = t.ensureSemantics();
      await _open(t);
      expect(
        find.bySemanticsLabel(
          'Emeka Nwosu, AC technician, verified. Rated 4.9 out of 5 from 128 '
          'reviews, 214 jobs done. Free now, based in Wuse 2, usually '
          'replies in about 10 minutes. From 8,000 naira',
        ),
        findsOneWidget,
      );
      // Someone busy says when they are next free.
      expect(
        find.bySemanticsLabel(RegExp(
          r'^Chinedu Eze, Auto mechanic, verified\. .* Free tomorrow at '
          r'9\sAM, based in Jabi,',
        )),
        findsOneWidget,
      );
      await t.tap(find.text('Emeka Nwosu'));
      await _wait(t, const Duration(milliseconds: 300));
      expect(
        find.text('Artisan profiles are next in the redesign.'),
        findsOneWidget,
      );
      await _close(t);
      semantics.dispose();
    });

    testWidgets('with an area, give distances instead of where they are based',
        (t) async {
      final home = await _open(t);
      expect(find.textContaining('km'), findsNothing);
      unawaited(home.session.setArea('Wuse 2'));
      await _wait(t);
      expect(find.textContaining('1.2 km'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Emeka Nwosu, .* 1\.2 kilometres away')),
        findsOneWidget,
      );
      await _close(t);
    });

    testWidgets("a past hire reads as one stop, and Book again as another",
        (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, signedIn: true);
      final hiredOn = MockData.hiredBeforeBy(
        'u_chidinma',
        DateTime.now(),
      ).single.lastHiredOn;
      expect(
        find.bySemanticsLabel(RegExp(
          r'^Yusuf Abdullahi, Plumber, verified\. Rated 4\.8 out of 5 from 74 '
          r'reviews, 131 jobs done\. You hired Yusuf on '
          '${DateFormat('d MMMM').format(hiredOn)}'
          r' and rated the job 5 out of 5\. ',
        )),
        findsOneWidget,
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Book Yusuf Abdullahi again')),
        containsSemantics(isButton: true, hasTapAction: true),
      );
      await _close(t);
      semantics.dispose();
    });

    for (final scale in [1.0, 1.1, 1.3]) {
      testWidgets('at ${scale}x text on a 360pt phone, nothing is cut',
          (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(t, width: 360);
        // Sizes scale with the screen's width.
        const w = 360 / 390;
        expect(t.takeException(), isNull);
        final rows = find.byType(ClientArtisanRow);
        expect(rows, findsNWidgets(5));
        for (final row in t.widgetList<ClientArtisanRow>(rows)) {
          final box = find.byWidget(row);
          // No line of the row loses words to an ellipsis (a long name
          // may, by design; the price never does)...
          for (final paragraph in t.renderObjectList<RenderParagraph>(
            find.descendant(of: box, matching: find.byType(RichText)),
          )) {
            if (paragraph.text.toPlainText() == row.artisan.name) continue;
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '${row.artisan.name}: "${paragraph.text.toPlainText()}"',
            );
          }
          // ...the trade shows whole...
          expect(
            find.descendant(
              of: box,
              matching: find.textContaining(row.artisan.trade),
            ),
            findsOneWidget,
          );
          // ...and the row grows rather than clip its last line.
          final rect = t.getRect(box);
          expect(rect.height, greaterThanOrEqualTo(88 * w - 0.5));
          final lines = t
              .renderObjectList<RenderParagraph>(
                find.descendant(of: box, matching: find.byType(RichText)),
              )
              .map((p) => p.localToGlobal(Offset.zero).dy + p.size.height);
          expect(
            lines.reduce((a, b) => a > b ? a : b),
            lessThanOrEqualTo(rect.bottom - 14 * w + 0.5),
          );
        }
        await _close(t);
      });
    }
  });

  group('A new area', () {
    testWidgets('is announced once its artisans load, and not before',
        (t) async {
      final semantics = t.ensureSemantics();
      final home = await _open(t);
      expect(find.text('Top-rated in Abuja'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Showing')), findsNothing);

      unawaited(home.session.setArea('Wuse 2'));
      await t.pump();
      // Nothing to say while the new list loads.
      expect(find.bySemanticsLabel(RegExp('^Showing')), findsNothing);
      await _wait(t);
      // Home lists five.
      expect(
        t.getSemantics(
          find.bySemanticsLabel('Showing 5 top-rated artisans near Wuse 2'),
        ),
        containsSemantics(isLiveRegion: true),
      );

      unawaited(home.session.setArea('Gwarinpa'));
      await _wait(t);
      expect(
        find.bySemanticsLabel('Showing 5 top-rated artisans near Wuse 2'),
        findsNothing,
      );
      expect(
        t.getSemantics(
          find.bySemanticsLabel('Showing 5 top-rated artisans near Gwarinpa'),
        ),
        containsSemantics(isLiveRegion: true),
      );
      await _close(t);
      semantics.dispose();
    });

    testWidgets('is told once, not again on coming back to Home', (t) async {
      final semantics = t.ensureSemantics();
      final home = await _open(t);
      unawaited(home.session.setArea('Wuse 2'));
      await _wait(t);
      expect(find.bySemanticsLabel(RegExp('^Showing')), findsOneWidget);

      await t.tap(find.text('Explore'));
      await _wait(t, const Duration(milliseconds: 600));
      await t.tap(find.text('Home'));
      await _wait(t, const Duration(milliseconds: 600));
      expect(find.text('Top-rated near you'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Showing')), findsNothing);
      await _close(t);
      semantics.dispose();
    });

    testWidgets('with nobody listed says so, and points to what to do next',
        (t) async {
      final semantics = t.ensureSemantics();
      final home = await _open(t, artisans: _ScriptedArtisans([<Artisan>[]]));
      expect(find.text('No artisans listed in Abuja yet'), findsOneWidget);
      expect(
        find.text("Post your job and we'll find someone for you."),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _header('Top-rated in Abuja'),
          matching: find.text('See all'),
        ),
        findsNothing,
      );
      // The way out is the post-a-job row right below.
      expect(find.text('Not sure who to pick?'), findsOneWidget);

      unawaited(home.session.setArea('Wuse 2'));
      await _wait(t);
      expect(find.text('No artisans listed near you yet'), findsOneWidget);
      expect(
        find.text(
          "Try another area, or post your job and we'll find someone.",
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Change area'), findsOneWidget);
      expect(
        t.getSemantics(
          find.bySemanticsLabel('No artisans listed near Wuse 2 yet'),
        ),
        containsSemantics(isLiveRegion: true),
      );
      // The note itself is one stop, and its button the next.
      expect(
        find.bySemanticsLabel(
          'No artisans listed near you yet\n'
          "Try another area, or post your job and we'll find someone.",
        ),
        findsOneWidget,
      );
      await _close(t);
      semantics.dispose();
    });
  });

  group('A failed refresh', () {
    testWidgets('keeps what loaded and offers to try again', (t) async {
      final artisans = _ScriptedArtisans([
        MockData.artisans,
        Exception('offline'),
        MockData.artisans,
      ]);
      await _open(t, artisans: artisans, height: 844);
      await _pullToRefresh(t);
      expect(find.text("We couldn't refresh everything."), findsOneWidget);
      // The artisans that loaded before are still there.
      await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await _wait(t, const Duration(milliseconds: 300));
      expect(find.text("We couldn't load artisans."), findsNothing);
      expect(find.byType(ClientArtisanRow), findsWidgets);

      await t.tap(find.widgetWithText(SnackBarAction, 'Try again'));
      await _wait(t, const Duration(milliseconds: 1500));
      expect(artisans.calls, 3);
      expect(find.text("We couldn't refresh everything."), findsNothing);
      await _close(t);
    });

    testWidgets('waits for screen reader users, and only for them', (t) async {
      final artisans = _ScriptedArtisans([
        MockData.artisans,
        Exception('offline'),
      ]);
      await _open(t, artisans: artisans, height: 844);
      await _pullToRefresh(t);
      expect(find.text("We couldn't refresh everything."), findsOneWidget);
      await _wait(t, const Duration(seconds: 6));
      expect(find.text("We couldn't refresh everything."), findsNothing);

      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pullToRefresh(t);
      await _wait(t, const Duration(seconds: 6));
      expect(find.text("We couldn't refresh everything."), findsOneWidget);
      await _close(t);
    });
  });

  testWidgets('sections that fail to load say so, each with a retry',
      (t) async {
    await _open(
      t,
      signedIn: true,
      artisans: _ScriptedArtisans([Exception('offline')]),
      catalog: _FailingCatalog(),
      bookings: _FailingBookings(),
    );
    expect(find.text("We couldn't load your bookings."), findsOneWidget);
    expect(find.text("We couldn't load services."), findsOneWidget);
    expect(find.text("We couldn't load artisans."), findsOneWidget);
    expect(find.text("We couldn't load prices."), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Try again'), findsNWidgets(4));
    // Without the trades, "Free now" and "All" still filter.
    expect(find.widgetWithText(AppChip, 'Free now'), findsOneWidget);
    expect(find.widgetWithText(AppChip, 'All'), findsOneWidget);
    await _close(t);
  });

  testWidgets('a call with no number to dial says so, not blaming the phone',
      (t) async {
    await _open(t, signedIn: true, bookings: _NoNumberBookings());
    await t.tap(find.bySemanticsLabel('Call Emeka'));
    await _wait(t, const Duration(milliseconds: 300));
    expect(
        find.text("There's no number to call Emeka on yet."), findsOneWidget);
    await _close(t);
  });

  testWidgets('the payment promise is read as one stop', (t) async {
    final semantics = t.ensureSemantics();
    await _open(t);
    expect(
      find.bySemanticsLabel(
        'Pay through RijHub. Your money is held until you confirm the job '
        'is done.',
      ),
      findsOneWidget,
    );
    await _close(t);
    semantics.dispose();
  });

  testWidgets('the post-a-job row asks a guest to sign in for it', (t) async {
    final home = await _open(t);
    await t.tap(find.text('Not sure who to pick?'));
    await t.pump();
    expect(home.prompts, [AuthPrompt.postJob]);
    await _close(t);
  });

  testWidgets('follows dark mode', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await _open(t, signedIn: true);
    expect(t.takeException(), isNull);
    final context = t.element(find.text('Top-rated near you'));
    expect(context.colors, AppColors.dark);
    // Words take the dark theme's ink, not the light one's.
    final title = t.renderObject<RenderParagraph>(
      find.text('Top-rated near you'),
    );
    expect(title.text.style!.color, AppColors.dark.textPrimary);
    expect(_herBooking, findsOneWidget);
    await _close(t);
  });
}
