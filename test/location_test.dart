// The area picker: its chrome next to the sign-in sheet's, and what it
// gives screen readers, keyboards and people who turn motion off.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:rijhub/app/session.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/data/mock/mock_repositories.dart';
import 'package:rijhub/data/models/models.dart';
import 'package:rijhub/data/repositories/repositories.dart';
import 'package:rijhub/features/location/area_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the picker resolved to.
class _Result {
  bool closed = false;
  String? area;
}

/// A screen with a button that opens the picker, on mock data.
Future<_Result> _pump(
  WidgetTester t, {
  String? current,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final session = SessionController(
    prefs: await SharedPreferences.getInstance(),
    auth: MockAuthRepository(),
  );
  await session.continueAsGuest(UserRole.client);

  final result = _Result();
  await t.pumpWidget(MultiProvider(
    providers: [
      Provider<CatalogRepository>.value(value: MockCatalogRepository()),
      ChangeNotifierProvider.value(value: session),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        // As RijHubApp does for iOS Reduce Motion: only MediaQuery knows.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result.area = await showAreaPicker(context, current: current);
                  result.closed = true;
                },
                child: const Text('Change area'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  return result;
}

/// Opens the picker and waits for the sheet and the mock's list of areas.
Future<_Result> _open(
  WidgetTester t, {
  String? current,
  Brightness brightness = Brightness.light,
}) async {
  final result = await _pump(t, current: current, brightness: brightness);
  await t.tap(find.text('Change area'));
  await _wait(t);
  return result;
}

/// Pumps [total] of fake time in short frames.
Future<void> _wait(
  WidgetTester t, [
  Duration total = const Duration(milliseconds: 600),
]) async {
  const frame = Duration(milliseconds: 50);
  for (var waited = Duration.zero; waited < total; waited += frame) {
    await t.pump(frame);
  }
}

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> _press(
  WidgetTester t,
  LogicalKeyboardKey key, {
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    await t.sendKeyEvent(key);
    await t.pump();
  }
}

void main() {
  testWidgets('closes from the same top row as the sign-in sheet', (t) async {
    await _open(t);
    final sheet = t.getRect(find.byType(BottomSheet));
    final close = t.getRect(_inSheet(find.bySemanticsLabel('Close')));
    final title = _inSheet(find.text('Choose your area'));
    // On the handle's row at the top right, above the title.
    expect(close.top - sheet.top, lessThan(1));
    expect(sheet.right - close.right, closeTo(4, 0.5));
    expect(close.bottom, lessThanOrEqualTo(t.getRect(title).top));
    // Titled like every other sheet and screen.
    expect(t.widget<Text>(title).style!.fontSize, AppText.headline.fontSize);
  });

  testWidgets(
      'screen readers find one close in the sheet and a named page '
      'around it', (t) async {
    final semantics = t.ensureSemantics();
    await _open(t);
    expect(find.bySemanticsLabel('Dismiss'), findsNothing);
    expect(find.bySemanticsLabel('Scrim'), findsNothing);
    expect(_inSheet(find.bySemanticsLabel('Close')), findsOneWidget);
    // The dimmed page above the sheet, which closes it too.
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == 'Close' &&
            node.getSemanticsData().hasAction(SemanticsAction.dismiss),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('the search field keeps its name once something is typed',
      (t) async {
    final semantics = t.ensureSemantics();
    await _open(t);
    await t.enterText(_inSheet(find.byType(TextField)), 'gwa');
    await _wait(t, const Duration(milliseconds: 200));
    final field =
        find.semantics.byFlag(SemanticsFlag.isTextField).evaluate().single;
    expect(field.label, 'Search areas');
    expect(field.value, 'gwa');
    semantics.dispose();
  });

  testWidgets('screen readers hear what matched once typing pauses', (t) async {
    final semantics = t.ensureSemantics();
    await _open(t);
    final field = _inSheet(find.byType(TextField));
    t.takeAnnouncements();
    await t.enterText(field, 'Lek');
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(field, 'Lekki');
    await _wait(t, const Duration(milliseconds: 900));
    expect(
      t.takeAnnouncements().map((a) => a.message),
      ['No areas match "Lekki"'],
    );

    await t.enterText(field, 'gw');
    await _wait(t, const Duration(milliseconds: 900));
    expect(t.takeAnnouncements().map((a) => a.message), ['2 areas match']);

    // Clearing the search shows every area again, without a word.
    await t.enterText(field, 'gwa');
    await t.tap(_inSheet(find.bySemanticsLabel('Clear search')));
    await _wait(t, const Duration(milliseconds: 900));
    expect(t.takeAnnouncements(), isEmpty);

    // Nor once an area is chosen and the sheet is closing.
    await t.enterText(field, 'gwa');
    await _wait(t, const Duration(milliseconds: 600));
    await t.tap(_inSheet(find.text('Gwarinpa')));
    await _wait(t, const Duration(milliseconds: 600));
    expect(t.takeAnnouncements(), isEmpty);
    semantics.dispose();
  });

  testWidgets('the chosen area is ticked in the crimson for thin marks',
      (t) async {
    await _open(t, current: 'Asokoro', brightness: Brightness.dark);
    final colors = t.element(find.byType(AreaPickerSheet)).colors;
    final tick = t.widget<Icon>(
      _inSheet(find.byIcon(IconsaxPlusBold.tick_circle)),
    );
    // In dark mode the brand crimson is about 2:1 on the sheet.
    expect(tick.color, colors.brandStroke);
    expect(tick.color, isNot(colors.brand));
  });

  testWidgets('a keyboard can choose an area', (t) async {
    final result = await _open(t);
    // Close, the search field, "Use my location", Apo, then Asokoro.
    await _press(t, LogicalKeyboardKey.tab, times: 5);
    await _press(t, LogicalKeyboardKey.enter);
    await _wait(t);
    expect(result.closed, isTrue);
    expect(result.area, 'Asokoro');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Enter pressed twice closes only the picker', (t) async {
    final result = await _open(t);
    // Close, the search field, "Use my location", then Apo.
    await _press(t, LogicalKeyboardKey.tab, times: 4);
    await _press(t, LogicalKeyboardKey.enter, times: 2);
    await _wait(t);
    expect(result.area, 'Apo');
    expect(find.text('Change area'), findsOneWidget);
  });

  testWidgets('rises and closes at once under reduced motion', (t) async {
    await _pump(t, reduceMotion: true);
    await t.tap(find.text('Change area'));
    await t.pump();
    final route = ModalRoute.of(t.element(find.byType(AreaPickerSheet)))!;
    expect(route.animation!.status, AnimationStatus.completed);

    await _wait(t);
    await t.tap(_inSheet(find.bySemanticsLabel('Close')));
    await t.pump();
    expect(find.byType(BottomSheet), findsNothing);
  });
}
