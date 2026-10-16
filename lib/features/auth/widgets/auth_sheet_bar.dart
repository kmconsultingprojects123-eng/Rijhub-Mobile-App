import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

/// The sheet's top row: back (when there is a step to go back to), the drag
/// handle and close. Sharing one row keeps the steps high enough to stay
/// above the keyboard on small phones.
class AuthSheetBar extends StatelessWidget {
  const AuthSheetBar({
    super.key,
    required this.onClose,
    this.showBack = false,
    this.onBack,
  });

  final VoidCallback onClose;

  /// Whether the step has a back button.
  final bool showBack;

  /// Null greys the back button out while the step is busy.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sheet = Theme.of(context).bottomSheetTheme;
    final handle = sheet.dragHandleSize ?? const Size(32, 4);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.s4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: AppSize.minTapTarget,
            child: AnimatedSwitcher(
              duration: context.motion(AppMotion.base),
              child: showBack
                  ? AppIconButton(
                      icon: IconsaxPlusLinear.arrow_left,
                      onPressed: onBack,
                      semanticLabel: 'Back',
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: handle.width,
                height: handle.height,
                decoration: BoxDecoration(
                  color: sheet.dragHandleColor ?? c.borderStrong,
                  borderRadius: AppRadius.pillAll,
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: IconsaxPlusLinear.close_circle,
            onPressed: onClose,
            semanticLabel: 'Close',
            iconColor: c.textSecondary,
          ),
        ],
      ),
    );
  }
}
