import 'package:flutter/widgets.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Icons for service categories, keyed by `ServiceCategory.iconKey`.
abstract final class CategoryIcons {
  static const _icons = <String, IconData>{
    'ac': IconsaxPlusLinear.wind,
    'electrical': IconsaxPlusLinear.flash_1,
    'plumbing': IconsaxPlusLinear.drop,
    'generator': IconsaxPlusLinear.electricity,
    'cleaning': IconsaxPlusLinear.broom,
    'mechanic': IconsaxPlusLinear.car,
    'solar': IconsaxPlusLinear.sun_1,
    'carpentry': IconsaxPlusLinear.ruler,
    'painting': IconsaxPlusLinear.brush_3,
    'tailoring': IconsaxPlusLinear.scissor,
    'gardening': IconsaxPlusLinear.tree,
    'moving': IconsaxPlusLinear.truck,
    'pest': IconsaxPlusLinear.shield_tick,
    'tv': IconsaxPlusLinear.monitor,
  };

  static IconData of(String key) => _icons[key] ?? IconsaxPlusLinear.category;
}
