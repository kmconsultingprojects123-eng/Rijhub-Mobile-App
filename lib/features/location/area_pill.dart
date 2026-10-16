import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import 'area_picker_sheet.dart';

/// The area "near you" results use, as a compact pill that opens the area
/// picker. Shows "Abuja" until someone picks a neighbourhood. Both homes
/// put it at the top left.
class AreaPill extends StatelessWidget {
  const AreaPill({super.key});

  /// Shown before an area is picked: results cover the whole city.
  static const city = 'Abuja';

  Future<void> _pick(BuildContext context) async {
    final session = context.read<SessionController>();
    final area = await showAreaPicker(context, current: session.area);
    if (area != null) await session.setArea(area);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final place = context.select<SessionController, String>(
      (s) => s.area ?? city,
    );
    return Pressable(
      onTap: () => _pick(context),
      semanticLabel: 'Area: $place. Change',
      focusRadius: AppRadius.pillAll,
      // A 48-point touch area around the 36-point pill.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            height: 36.w,
            padding: EdgeInsetsDirectional.only(
              start: AppSpace.s12,
              end: AppSpace.s8,
            ),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: AppRadius.pillAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  IconsaxPlusBold.location,
                  size: AppSize.iconSmall,
                  color: c.brandText,
                ),
                SizedBox(width: AppSpace.s6),
                Flexible(
                  child: Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Hugs a shortened name, so the arrow follows it.
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: AppText.labelSmall.copyWith(color: c.textPrimary),
                  ),
                ),
                SizedBox(width: AppSpace.s4),
                Icon(
                  IconsaxPlusLinear.arrow_down,
                  size: 14.w,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
