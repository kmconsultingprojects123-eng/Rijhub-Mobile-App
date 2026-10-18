// Runs before every test file here: loads the app's real fonts, so text
// measures as it does on a phone instead of in the test font, where every
// letter is a full square and lines overflow that never would.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(rootBundle.load('assets/fonts/inter/Inter-$weight.ttf'));
  }
  await inter.load();
  for (final family in ['IconsaxPlusLinear', 'IconsaxPlusBold']) {
    await (FontLoader('packages/iconsax_plus/$family')
          ..addFont(rootBundle.load('packages/iconsax_plus/fonts/$family.ttf')))
        .load();
  }
  for (final (family, file) in [
    ('FontAwesomeBrands', 'Font-Awesome-7-Brands-Regular-400.otf'),
    ('FontAwesomeSolid', 'Font-Awesome-7-Free-Solid-900.otf'),
  ]) {
    await (FontLoader('packages/font_awesome_flutter/$family')
          ..addFont(
              rootBundle.load('packages/font_awesome_flutter/lib/fonts/$file')))
        .load();
  }
  await testMain();
}
