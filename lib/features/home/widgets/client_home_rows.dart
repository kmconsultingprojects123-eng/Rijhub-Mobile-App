import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

/// For clients who would rather not choose: post the job once and let
/// artisans come with quotes. A quiet row under the list, not a banner.
class ClientPostJobRow extends StatelessWidget {
  const ClientPostJobRow({super.key, required this.onTap});

  final VoidCallback onTap;

  static const title = 'Not sure who to pick?';
  static const message = 'Describe the job once and get quotes';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tile = 40.w;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title Post a job: describe it once and get quotes '
          'from artisans',
      focusRadius: AppRadius.lgAll,
      child: Container(
        constraints: BoxConstraints(minHeight: 64.w),
        padding: EdgeInsets.all(AppSpace.s12),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                color: c.brandSubtle,
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                IconsaxPlusLinear.clipboard_text,
                size: 20.w,
                color: c.brandText,
              ),
            ),
            SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppText.titleSmall.copyWith(color: c.textPrimary),
                  ),
                  SizedBox(height: AppSpace.s2),
                  Text(
                    message,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpace.s8),
            Icon(
              IconsaxPlusLinear.arrow_right_3,
              size: AppSize.iconSmall,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the list says when nobody fits the filters or the area, with the
/// one step most likely to fix it (posting a job is the row below).
class ClientEmptyNote extends StatelessWidget {
  const ClientEmptyNote({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A small text button's label sits this far inside its edge.
  static const _buttonInset = 14.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actionLabel = this.actionLabel;
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpace.s16,
        AppSpace.s16,
        AppSpace.s16,
        actionLabel == null ? AppSpace.s16 : AppSpace.s4,
      ),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            IconsaxPlusLinear.user_search,
            size: AppSize.icon,
            color: c.textSecondary,
          ),
          SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // One stop for screen readers; the button is the next.
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppText.titleSmall.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppSpace.s2),
                      Text(
                        message,
                        style: AppText.bodySmall.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  // Its label lines up with the words above.
                  Transform.translate(
                    offset: Offset(ltr ? -_buttonInset : _buttonInset, 0),
                    child: AppButton(
                      label: actionLabel,
                      variant: AppButtonVariant.tertiary,
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed: onAction,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The payment promise, in one quiet line under everything else.
class ClientTrustStrip extends StatelessWidget {
  const ClientTrustStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One stop for screen readers.
    return MergeSemantics(
      child: Container(
        constraints: BoxConstraints(minHeight: math.max(56, 56.w)),
        padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
        child: Row(
          children: [
            Icon(
              IconsaxPlusBold.shield_tick,
              size: AppSize.icon,
              color: c.success,
            ),
            SizedBox(width: AppSpace.s12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Pay through RijHub. ',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: 'Your money is held until you confirm the job '
                          'is\u00A0done.',
                    ),
                  ],
                ),
                style: AppText.bodySmall.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// For guests who came to work rather than to hire: switches them to the
/// artisan side.
class ClientRoleLink extends StatelessWidget {
  const ClientRoleLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Do you fix things? Find work on RijHub',
      focusRadius: AppRadius.mdAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Do you fix things? ',
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                  TextSpan(
                    text: 'Find work on RijHub',
                    style: AppText.labelSmall.copyWith(color: c.brandText),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
