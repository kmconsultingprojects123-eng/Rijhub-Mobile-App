import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

/// The way into search on the client Home: shaped like a field, it opens
/// Explore, where searching happens. A voice button sits at its end.
///
/// It asks the question in the client's words, since people know what's
/// wrong long before they know which trade fixes it.
class ClientSearchBar extends StatelessWidget {
  const ClientSearchBar({
    super.key,
    required this.onTap,
    required this.onVoiceTap,
  });

  final VoidCallback onTap;
  final VoidCallback onVoiceTap;

  static const placeholder = 'What needs fixing?';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = math.max(AppSize.minTapTarget, 48.w);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        children: [
          Pressable(
            onTap: onTap,
            semanticLabel: 'Search. $placeholder',
            focusRadius: AppRadius.mdAll,
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              padding: EdgeInsetsDirectional.only(
                start: AppSpace.s16,
                // Clear of the voice button.
                end: AppSize.minTapTarget,
              ),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(
                    IconsaxPlusLinear.search_normal_1,
                    size: 20.w,
                    color: c.textSecondary,
                  ),
                  SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Text(
                      placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyLarge.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Over the field rather than inside it, so it is a tap target
          // and a stop for screen readers of its own.
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            child: Center(
              child: Pressable(
                onTap: onVoiceTap,
                semanticLabel: 'Search by voice',
                pressedScale: 0.92,
                focusRadius: AppRadius.pillAll,
                focusOffset: 0,
                child: SizedBox.square(
                  dimension: AppSize.minTapTarget,
                  child: Icon(
                    IconsaxPlusLinear.microphone_2,
                    size: 20.w,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
