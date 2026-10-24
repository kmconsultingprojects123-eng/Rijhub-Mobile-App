import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';

/// Shown next to the name of an artisan whose identity has been verified.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Verified',
      child: Icon(
        IconsaxPlusBold.verify,
        size: size,
        color: context.colors.verified,
      ),
    );
  }
}

/// ★ 4.9 (128)
class RatingLabel extends StatelessWidget {
  const RatingLabel({
    super.key,
    required this.rating,
    this.count,
    this.color,
  });

  final double rating;
  final int? count;

  /// Text colour; defaults to the primary text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textColor = color ?? c.textPrimary;
    // No reviews yet: "New", not a 0.0 that reads as a bad rating.
    if (count == 0 || rating <= 0) {
      return Semantics(
        label: 'New on Employi, no reviews yet',
        excludeSemantics: true,
        child: Text('New',
            style: AppText.caption
                .copyWith(color: textColor, fontWeight: FontWeight.w600)),
      );
    }
    return Semantics(
      label: count == null
          ? 'Rated ${rating.toStringAsFixed(1)} out of 5'
          : 'Rated ${rating.toStringAsFixed(1)} out of 5 from $count reviews',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusBold.star_1, size: 14, color: c.rating),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: AppText.caption.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 3),
            Text(
              '($count)',
              style: AppText.caption.copyWith(
                color: color?.withValues(alpha: 0.8) ?? c.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum TagTone { neutral, brand, success, warning, info }

/// A small status label, for example "Urgent" or "Confirmed".
class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.label,
    this.tone = TagTone.neutral,
    this.icon,
  });

  final String label;
  final TagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color fg) = switch (tone) {
      TagTone.neutral => (c.surfaceMuted, c.textSecondary),
      TagTone.brand => (c.brandSubtle, c.brandText),
      TagTone.success => (c.successSubtle, c.success),
      TagTone.warning => (c.warningSubtle, c.warning),
      TagTone.info => (c.infoSubtle, c.info),
    };
    return Container(
      // The same pill as the badges on artisan photos.
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.s8,
        vertical: AppSpace.s4,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppText.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
