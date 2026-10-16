import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'artisan_format.dart';
import 'artisan_job_row.dart';
import 'artisan_meta_line.dart';

/// The one setup step that stops clients booking a new artisan (the ID
/// check), as a banner under the top bar. Steps that don't block bookings
/// never get one; they get [ArtisanSetupRow] below the work.
class ArtisanSetupBanner extends StatelessWidget {
  const ArtisanSetupBanner({
    super.key,
    required this.step,
    required this.onStart,
  });

  final SetupStep step;
  final VoidCallback onStart;

  /// "Verify your ID to start getting booked".
  static String title(SetupStep step) => step.id == 'identity'
      ? 'Verify your ID to start getting booked'
      : '${step.label} to start getting booked';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final heading = title(step);
    final effort = step.effort;
    return Pressable(
      onTap: onStart,
      semanticLabel: [
        heading,
        if (effort != null)
          effort.replaceAll(' · ', ', ').replaceAll('+', 'and'),
        'Start',
      ].join('. '),
      focusRadius: AppRadius.lgAll,
      child: Container(
        // 12 + 20 + 2 + 36 + 10: 80 at most, as a banner should be.
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpace.s12,
          AppSpace.s12,
          AppSpace.s12,
          10.w,
        ),
        decoration: BoxDecoration(
          color: c.warningSubtle,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtisanTradeTile(
              icon: IconsaxPlusLinear.personalcard,
              color: c.surface,
              iconColor: c.warning,
            ),
            SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ArtisanFormat.noWidow(heading),
                    style: AppText.titleSmall.copyWith(color: c.textPrimary),
                  ),
                  SizedBox(height: AppSpace.s2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          effort ?? '',
                          style: AppText.bodySmall.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      SizedBox(width: AppSpace.s8),
                      const _ActionPill(label: 'Start'),
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
}

/// The week in one 56pt row: jobs, rating with its review count, and how
/// often the artisan replies. Earnings and stats get a tab of their own.
class ArtisanWeekRow extends StatelessWidget {
  const ArtisanWeekRow({
    super.key,
    required this.dashboard,
    required this.onTap,
  });

  final ArtisanDashboard dashboard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final jobs = dashboard.jobsThisWeek;
    final reviews = dashboard.reviewCount;
    final rating = dashboard.rating.toStringAsFixed(1);
    final strong = TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600);
    final jobsText = '$jobs ${jobs == 1 ? 'job' : 'jobs'}';
    // A new account has had no requests to answer, so it has no rate yet.
    final hasReplies = dashboard.responseRate > 0 || reviews > 0;
    const keep = '\u00A0';

    return _LinkRow(
      onTap: onTap,
      semanticLabel: [
        'This week: $jobsText',
        if (reviews > 0)
          'rated $rating out of 5 from $reviews '
              '${reviews == 1 ? 'review' : 'reviews'}'
        else
          'no reviews yet',
        if (hasReplies) 'replies to ${dashboard.responseRate}% of requests',
      ].join(', '),
      minHeight: 56.w,
      leading: const ArtisanTradeTile(icon: IconsaxPlusLinear.status_up),
      // "This week · 6 jobs · ★ 4.9 (128) · replies 96%", with the star
      // drawn as on the client's rows.
      child: ArtisanMetaLine(
        style: AppText.bodySmall.copyWith(color: c.textSecondary),
        facts: [
          TextSpan(text: 'This${keep}week', style: strong),
          TextSpan(text: jobsText.replaceAll(' ', keep)),
          if (reviews > 0)
            TextSpan(
              children: [
                TextSpan(text: '★$keep', style: TextStyle(color: c.rating)),
                TextSpan(text: rating, style: strong),
                TextSpan(text: '$keep($reviews)'),
              ],
            )
          else
            const TextSpan(text: 'No reviews yet'),
          if (hasReplies)
            TextSpan(text: 'replies$keep${dashboard.responseRate}%'),
        ],
      ),
    );
  }
}

/// The next setup step that doesn't block bookings, as one 64pt row with
/// a ring showing how far setup has come.
class ArtisanSetupRow extends StatelessWidget {
  const ArtisanSetupRow({
    super.key,
    required this.step,
    required this.done,
    required this.total,
    required this.onTap,
  });

  final SetupStep step;
  final int done;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reason = step.reason;
    return _LinkRow(
      onTap: onTap,
      semanticLabel: [
        'Profile setup, $done of $total steps done',
        'Next: ${step.label}',
        if (reason != null) reason,
      ].join('. '),
      minHeight: 64.w,
      leading: _ProgressRing(done: done, total: total),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.label,
            style: AppText.titleSmall.copyWith(color: c.textPrimary),
          ),
          if (reason != null)
            Text(
              ArtisanFormat.noWidow(reason),
              style: AppText.bodySmall.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A flat row that leads somewhere else (earnings, profile setup): a 36pt
/// leading tile in the job rows' column, its words, and a chevron.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.leading,
    required this.child,
    required this.semanticLabel,
    required this.minHeight,
    required this.onTap,
  });

  final Widget leading;
  final Widget child;
  final String semanticLabel;
  final double minHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The chevron's stroke sits in the middle of its 16pt glyph. The glyph
    // reaches 4pt into the gutter, so the stroke lines up with the content
    // above and the words get that much more room.
    final chevronReach = 4.w;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      pressedScale: 0.99,
      focusRadius: BorderRadius.zero,
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpace.gutter,
            10.w,
            AppSpace.gutter - chevronReach,
            10.w,
          ),
          child: Row(
            children: [
              leading,
              SizedBox(width: AppSpace.s16),
              Expanded(child: child),
              SizedBox(width: AppSpace.s4),
              Icon(
                IconsaxPlusLinear.arrow_right_3,
                size: AppSize.iconSmall,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3/4" inside a ring that fills as setup steps are done.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The size of the tiles that start the other rows.
    final size = ArtisanJobRow.tileSize;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: total == 0 ? 0 : done / total,
          track: c.border,
          fill: c.brandStroke,
          width: 3.w,
        ),
        // The count grows a little with large text but stays clear of the
        // ring; the row's label says it in words.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: Center(
            child: Text(
              '$done/$total',
              maxLines: 1,
              style: AppText.caption.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.fill,
    required this.width,
  });

  final double progress;
  final Color track;
  final Color fill;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        paint..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.width != width;
}

/// The guest's invitation, placed among the jobs: quote on work like this
/// with a free profile. The whole row is the way in.
class ArtisanJoinRow extends StatelessWidget {
  const ArtisanJoinRow({super.key, required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Pressable(
        onTap: onJoin,
        semanticLabel: 'Quote on jobs like these. Free, takes about a '
            'minute, just your phone number. Join free',
        focusRadius: AppRadius.lgAll,
        child: Container(
          constraints: BoxConstraints(minHeight: 64.w),
          padding: EdgeInsets.all(AppSpace.s12),
          decoration: BoxDecoration(
            color: c.brandSubtle,
            borderRadius: AppRadius.lgAll,
          ),
          child: Row(
            children: [
              ArtisanTradeTile(
                icon: IconsaxPlusLinear.briefcase,
                color: c.surface,
                iconColor: c.brandText,
              ),
              SizedBox(width: AppSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // "like these" stays together if the line breaks.
                      'Quote on jobs like\u00A0these',
                      style: AppText.titleSmall.copyWith(color: c.textPrimary),
                    ),
                    const _JoinTerms(),
                  ],
                ),
              ),
              SizedBox(width: AppSpace.s8),
              const _ActionPill(label: 'Join free'),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Free · just your phone number" on one line, which keeps the row at
/// 64pt. With larger text, two lines that break between phrases, never
/// inside one: "Free · 1 minute" over "Just your phone number".
class _JoinTerms extends StatelessWidget {
  const _JoinTerms();

  static const _oneLine = 'Free · just your phone number';
  static const _twoLines = 'Free · 1 minute\nJust your phone number';

  @override
  Widget build(BuildContext context) {
    final style =
        AppText.bodySmall.copyWith(color: context.colors.textSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: _oneLine, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        painter.dispose();
        return Text(fits ? _oneLine : _twoLines, style: style);
      },
    );
  }
}

/// A small filled button shape inside a row that is itself the target, so
/// the row reads as having one clear action.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(minHeight: AppSize.buttonSmall),
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.brand, borderRadius: AppRadius.mdAll),
      child: Text(
        label,
        maxLines: 1,
        style: AppText.labelSmall.copyWith(color: c.onBrand),
      ),
    );
  }
}

/// "See all 126 jobs ›", closing a list of jobs, lined up with the rows'
/// text.
class ArtisanSeeAllRow extends StatelessWidget {
  const ArtisanSeeAllRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRadius: BorderRadius.zero,
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: ArtisanJobRow.textStart,
            end: AppSpace.gutter,
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppText.labelSmall.copyWith(color: c.brandText),
                ),
              ),
              SizedBox(width: AppSpace.s4),
              Icon(
                IconsaxPlusLinear.arrow_right_3,
                size: AppSize.iconSmall,
                color: c.brandText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line on how money moves, under the guest's jobs.
class ArtisanTrustLine extends StatelessWidget {
  const ArtisanTrustLine({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppText.bodySmall.copyWith(color: c.textSecondary);
    // The shield centres on the first line at any text size.
    final firstLine =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: firstLine,
            child: Icon(
              IconsaxPlusBold.shield_tick,
              size: AppSize.iconSmall,
              color: c.success,
            ),
          ),
          SizedBox(width: AppSpace.s8),
          Expanded(
            // A sentence a line, so neither is left with one word.
            child: Text(
              "Clients pay into RijHub.\nYou're paid when the job is done.",
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
