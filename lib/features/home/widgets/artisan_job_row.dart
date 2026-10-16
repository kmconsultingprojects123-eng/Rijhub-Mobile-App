import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'artisan_format.dart';
import 'artisan_meta_line.dart';

/// An open job as a flat, 88pt list row: what it is, the budget and where,
/// then how fresh it is and how many have quoted. The whole row opens the
/// job sheet; there are no buttons in it.
class ArtisanJobRow extends StatelessWidget {
  const ArtisanJobRow({
    super.key,
    required this.job,
    required this.icon,
    required this.showDistance,
    required this.onTap,
    this.now,
  });

  final JobPost job;

  /// The job's trade.
  final IconData icon;

  /// Jobs are for a neighbourhood, so distances mean something. Without
  /// one (all of Abuja) the row names the area and nothing more.
  final bool showDistance;
  final VoidCallback onTap;

  /// When "12 min ago" is counted from. Defaults to the moment it builds.
  final DateTime? now;

  /// The trade tile's size.
  static double get tileSize => 36.w;

  /// Where the text column starts, from the screen's edge: the gutter, the
  /// tile and the gap after it. Hairlines between rows start here.
  static double get textStart => AppSpace.gutter + tileSize + AppSpace.s16;

  /// "Be the first to quote", "1 quote" or "3 quotes". The phrase never
  /// splits across lines.
  static String quotes(int count) => switch (count) {
        0 => 'Be\u00A0the\u00A0first\u00A0to\u00A0quote',
        1 => '1 quote',
        _ => '$count quotes',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = now ?? DateTime.now();
    final secondary = AppText.bodySmall.copyWith(color: c.textSecondary);
    final meta = AppText.caption.copyWith(color: c.textTertiary);
    // An amount stands out; "Open to quotes" reads as the words around it.
    final hasBudget = job.budgetMin != null || job.budgetMax != null;

    return Pressable(
      onTap: onTap,
      semanticLabel: _describe(at),
      pressedScale: 0.99,
      focusRadius: BorderRadius.zero,
      focusOffset: 0,
      child: Padding(
        // 15 above and below three lines (20 + 2 + 18 + 2 + 16) make 88.
        padding: EdgeInsets.symmetric(
          horizontal: AppSpace.gutter,
          vertical: 15.w,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtisanTradeTile(icon: icon),
            SizedBox(width: AppSpace.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSmall.copyWith(color: c.textPrimary),
                  ),
                  SizedBox(height: AppSpace.s2),
                  // Nothing here is cut short: a long area name or large
                  // text moves the next fact to a line of its own, and the
                  // row grows, as it does for a two-line title.
                  ArtisanMetaLine(
                    style: secondary,
                    facts: [
                      TextSpan(
                        text: ArtisanFormat.budget(
                          job.budgetMin,
                          job.budgetMax,
                        ).replaceAll(' ', '\u00A0'),
                        style: hasBudget
                            ? TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                      TextSpan(text: job.area),
                      if (showDistance)
                        TextSpan(text: ArtisanFormat.km(job.distanceKm)),
                    ],
                  ),
                  SizedBox(height: AppSpace.s2),
                  ArtisanMetaLine(
                    style: meta,
                    facts: [
                      if (job.isUrgent)
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsetsDirectional.only(
                                  end: AppSpace.s2,
                                ),
                                child: Icon(
                                  IconsaxPlusBold.timer_1,
                                  size: 13.w,
                                  color: c.warning,
                                ),
                              ),
                            ),
                            TextSpan(
                              text: 'Urgent',
                              style: TextStyle(
                                color: c.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      TextSpan(text: RelativeTime.short(job.postedAt, now: at)),
                      TextSpan(
                        text: quotes(job.quoteCount),
                        style: job.quoteCount == 0
                            ? TextStyle(color: c.success)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The row as sentences for screen readers, in the order it shows them,
  /// with times and money in words rather than symbols.
  String _describe(DateTime at) {
    final place = showDistance
        ? '${job.area}, ${ArtisanFormat.spokenKm(job.distanceKm)}'
        : job.area;
    final posted = RelativeTime.spoken(job.postedAt, now: at);
    return [
      job.title,
      ArtisanFormat.spokenBudget(job.budgetMin, job.budgetMax),
      place,
      if (job.isUrgent) 'Urgent',
      'Posted ${TextCase.midSentence(posted)}',
      quotes(job.quoteCount),
    ].join('. ');
  }
}

/// A hairline between job rows, starting at the text column.
class ArtisanRowDivider extends StatelessWidget {
  const ArtisanRowDivider({super.key, this.indent});

  /// Where it starts; defaults to the job rows' text column.
  final double? indent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent ?? ArtisanJobRow.textStart,
      color: context.colors.border,
    );
  }
}

/// A trade's icon on a quiet 36pt tile, at the start of a row.
class ArtisanTradeTile extends StatelessWidget {
  const ArtisanTradeTile({
    super.key,
    required this.icon,
    this.color,
    this.iconColor,
  });

  final IconData icon;

  /// Defaults to the muted surface.
  final Color? color;

  /// Defaults to the primary text colour.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = ArtisanJobRow.tileSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? c.surfaceMuted,
        borderRadius: BorderRadius.circular(10.w),
      ),
      child: Icon(icon, size: 18.w, color: iconColor ?? c.textPrimary),
    );
  }
}

/// A placeholder in the shape of [ArtisanJobRow], with bars centred on
/// its three lines. Place it inside a `SkeletonPulse`.
class ArtisanJobRowSkeleton extends StatelessWidget {
  const ArtisanJobRowSkeleton({super.key, this.titleWidth = 0.72});

  /// The title bar's share of the text column.
  final double titleWidth;

  @override
  Widget build(BuildContext context) {
    Widget line(double lineHeight, double barHeight, double share) => SizedBox(
          height: lineHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: share,
              child: SkeletonBox(height: barHeight),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.gutter,
        vertical: 15.w,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: ArtisanJobRow.tileSize,
            height: ArtisanJobRow.tileSize,
            radius: 10.w,
          ),
          SizedBox(width: AppSpace.s16),
          Expanded(
            child: Column(
              children: [
                line(20.sp, 13.w, titleWidth),
                SizedBox(height: AppSpace.s2),
                line(18.sp, 11.w, 0.58),
                SizedBox(height: AppSpace.s2),
                line(16.sp, 10.w, 0.44),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
