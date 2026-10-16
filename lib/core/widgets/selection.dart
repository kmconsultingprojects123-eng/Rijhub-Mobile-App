import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import 'pressable.dart';

/// A large radio-style option: icon, title and one line of explanation.
class SelectionCard extends StatelessWidget {
  const SelectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Pressable(
          onTap: onTap,
          semanticLabel: '$title. $subtitle',
          focusRadius: AppRadius.lgAll,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.base),
            curve: AppMotion.standard,
            padding: EdgeInsets.all(AppSpace.s16),
            decoration: BoxDecoration(
              color: selected ? c.brandSubtle : c.surface,
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: selected ? c.brandStroke : c.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: context.motion(AppMotion.base),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? c.brand : c.surfaceMuted,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Icon(
                    icon,
                    size: AppSize.iconLarge,
                    color: selected ? c.onBrand : c.textPrimary,
                  ),
                ),
                SizedBox(width: AppSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            AppText.titleSmall.copyWith(color: c.textPrimary),
                      ),
                      SizedBox(height: AppSpace.s4),
                      Text(
                        subtitle,
                        style: AppText.bodySmall.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpace.s12),
                _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: context.motion(AppMotion.base),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.brand : Colors.transparent,
        border: Border.all(
          color: selected ? c.brand : c.borderStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: c.onBrand)
          : null,
    );
  }
}

/// A pill-shaped filter or multi-select chip. It looks 32pt tall inside a
/// 48pt touch area, so a row of chips needs no run spacing (wrapped rows
/// sit 16pt apart). Give it an [icon], or a [dotColor] for a status filter
/// such as "Free now": selected, either becomes a tick.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dotColor,
    this.singleChoice = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// A small dot in place of an icon, for a status filter: the
  /// `context.colors.online` green for "Free now". Ignored when there is
  /// an [icon].
  final Color? dotColor;

  /// Set for filter rows where only one chip can be on, so screen readers
  /// announce each chip as one option of several.
  final bool singleChoice;

  /// The visible height. Like the touch area, it doesn't scale with the
  /// screen; it grows only when large text needs the room.
  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One node for screen readers: the label, the tap and the selection.
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: singleChoice ? true : null,
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          focusRadius: AppRadius.pillAll,
          // The 48pt touch area already rings the chip, and chip rows often
          // scroll inside a list that clips.
          focusOffset: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: _chipBody(context, c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipBody(BuildContext context, AppColors c) {
    // A selected chip swaps its icon or dot for a tick, so being selected
    // doesn't rest on colour alone. Only a swap, in a slot of one size, and
    // the label keeps its weight: a chip that grew would push the row along
    // under the finger that tapped it.
    final marked = icon != null || dotColor != null;
    final iconSize = AppSize.iconSmall;
    final Widget? leading = switch ((selected, icon, dotColor)) {
      (true, _, _) when marked => Icon(
          IconsaxPlusBold.tick_circle,
          size: iconSize,
          color: c.brandText,
        ),
      (_, final IconData glyph, _) =>
        Icon(glyph, size: iconSize, color: c.textSecondary),
      (_, _, final Color dot) => SizedBox.square(
          dimension: iconSize,
          child: Center(
            child: Container(
              width: AppSpace.s8,
              height: AppSpace.s8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
        ),
      _ => null,
    };
    return AnimatedContainer(
      duration: context.motion(AppMotion.fast),
      constraints: const BoxConstraints(minHeight: height),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.s12,
        vertical: AppSpace.s4,
      ),
      decoration: BoxDecoration(
        color: selected ? c.brandSubtle : c.surface,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: selected ? c.brandStroke : c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            SizedBox(width: AppSpace.s6),
          ],
          Text(
            label,
            style: AppText.labelSmall.copyWith(
              color: selected ? c.brandText : c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
