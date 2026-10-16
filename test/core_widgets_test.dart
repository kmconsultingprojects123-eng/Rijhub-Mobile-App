// What the design system's components tell screen readers and keyboards.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:rijhub/core/theme/theme.dart';
import 'package:rijhub/core/widgets/widgets.dart';

/// [child] on a phone-sized page with the app's theme.
Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(t.view.reset);
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  ));
  await t.pump();
}

/// Every semantics node that is a text field.
List<SemanticsNode> _textFields(WidgetTester t) =>
    find.semantics.byFlag(SemanticsFlag.isTextField).evaluate().toList();

void main() {
  group('Text fields', () {
    testWidgets('are named by their label, before and after typing', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(t, const AppTextField(label: 'Full name'));
      expect(_textFields(t).single.label, 'Full name');
      // The visible label isn't a second stop.
      expect(find.bySemanticsLabel('Full name'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Ada Obi');
      // Until the hint has faded out, it is read after the name.
      await t.pumpAndSettle();
      final field = _textFields(t).single;
      expect(field.label, 'Full name');
      expect(field.value, 'Ada Obi');
      semantics.dispose();
    });

    testWidgets('say "optional", and an error, on the field itself', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(
        t,
        const AppTextField(
          label: 'Email',
          optional: true,
          errorText: 'Check the email address',
        ),
      );
      final field = _textFields(t).single;
      expect(field.label, 'Email, optional');
      expect(field.hint, 'Check the email address');
      semantics.dispose();
    });

    testWidgets('can be named without a visible label', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(
        t,
        const AppTextField(
          semanticLabel: 'Search areas',
          hint: 'Search areas in Abuja',
        ),
      );
      await t.enterText(find.byType(TextField), 'Gwar');
      await t.pumpAndSettle();
      expect(_textFields(t).single.label, 'Search areas');
      semantics.dispose();
    });

    testWidgets('a phone number is named with its fixed +234', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(t, PhoneNumberField(controller: TextEditingController()));
      expect(
        _textFields(t).single.label,
        startsWith('Phone number, Nigeria +234'),
      );
      // The flag and +234 are part of the field, not a stop of their own.
      expect(find.bySemanticsLabel(RegExp('^Nigeria')), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('the code field is one named text field holding the digits',
      (t) async {
    final semantics = t.ensureSemantics();
    await _pump(
      t,
      OtpCodeField(controller: TextEditingController(text: '4829')),
    );
    final field = _textFields(t).single;
    expect(field.label, 'Verification code, 6 digits');
    expect(field.value, '4829');
    expect(
      field.getSemanticsData().hasAction(SemanticsAction.setText),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('the code field lets go of a focus node it no longer uses',
      (t) async {
    final first = FocusNode();
    final second = FocusNode();
    final code = TextEditingController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(code.dispose);
    var stage = 0;
    late StateSetter setStage;
    await _pump(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          setStage = setState;
          return Column(
            children: [
              if (stage < 2)
                OtpCodeField(
                  controller: code,
                  focusNode: stage == 0 ? first : second,
                  autofocus: false,
                ),
              if (stage == 2) Focus(focusNode: first, child: const SizedBox()),
            ],
          );
        },
      ),
    );
    // A new node, then the field goes and the old node is used elsewhere.
    setStage(() => stage = 1);
    await t.pump();
    setStage(() => stage = 2);
    await t.pump();
    first.requestFocus();
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('a button stays the same node when it starts loading', (t) async {
    final semantics = t.ensureSemantics();
    var loading = false;
    late StateSetter setLoading;
    await _pump(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          setLoading = setState;
          return AppButton(
            label: 'Send code',
            isLoading: loading,
            onPressed: () {},
          );
        },
      ),
    );
    final before = t.getSemantics(find.byType(AppButton));
    expect(before.label, 'Send code');

    setLoading(() => loading = true);
    await t.pump();
    final after = t.getSemantics(find.byType(AppButton));
    expect(after.id, before.id);
    expect(after.label, 'Send code, loading');
    semantics.dispose();
  });

  group('Keyboards', () {
    testWidgets('reach a pressable card, ring it and open it with Enter',
        (t) async {
      var opened = 0;
      await _pump(
        t,
        AppCard(
            onTap: () => opened++, child: const Text('Finish your profile')),
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);

      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final ring = t.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(Pressable),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(ring.foregroundPainter, isNotNull);

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(opened, 1);
    });

    testWidgets('see a ring around a focused button', (t) async {
      await _pump(t, AppButton(label: 'Post a job', onPressed: () {}));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      final button = find.byType(TextButton);
      BorderSide? side() => t.widget<TextButton>(button).style!.side!.resolve({
            if (Focus.of(t.element(find.text('Post a job'))).hasFocus)
              WidgetState.focused
          });

      expect(side(), isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(side()!.width, 2);
    });
  });

  testWidgets('a selected chip swaps its icon for a tick, keeping its width',
      (t) async {
    await _pump(
      t,
      const Wrap(
        children: [
          // No icon to swap, so no tick: the chip mustn't grow.
          AppChip(label: 'All', selected: true, onTap: _noop),
          AppChip(
            label: 'Solar',
            icon: IconsaxPlusLinear.sun_1,
            selected: true,
            onTap: _noop,
          ),
          AppChip(
            label: 'Plumbing',
            icon: IconsaxPlusLinear.drop,
            selected: false,
            onTap: _noop,
          ),
        ],
      ),
    );
    expect(find.byIcon(IconsaxPlusBold.tick_circle), findsOneWidget);
    expect(find.byIcon(IconsaxPlusLinear.sun_1), findsNothing);
    expect(find.byIcon(IconsaxPlusLinear.drop), findsOneWidget);
  });
}

void _noop() {}
