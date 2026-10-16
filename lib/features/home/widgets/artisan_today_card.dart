import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'artisan_format.dart';
import 'artisan_meta_line.dart';

/// A booking this close is "soon": its countdown turns amber.
const _soon = Duration(minutes: 30);

/// The width of the time column, so later bookings' times line up under
/// the first one's. Grows with the text size.
double _timeColumn(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(68.w);

/// The gap, divider and gap between the time column and the details.
double get _afterTime => 10.w + 1 + 12.w;

/// How far message and call reach into the details column from its end:
/// two 48pt touch areas, less the 8pt by which the card's end padding (12)
/// is wider than their inset from the card's edge (4).
double get _actionsWidth => 2 * AppSize.minTapTarget - (12.w - 4.w);

/// The day's bookings as one card, like an agenda: the next one in full
/// (when, what, who, where, with message and call), then a line for each
/// later one. Tapping the card opens the schedule.
class ArtisanTodayCard extends StatelessWidget {
  const ArtisanTodayCard({
    super.key,
    required this.bookings,
    required this.now,
    required this.showDistance,
    required this.onOpen,
    required this.onMessage,
    required this.onCall,
  });

  /// The day's bookings, soonest first. Not empty.
  final List<Booking> bookings;
  final DateTime now;

  /// Bookings carry distances from the artisan, shown while jobs are for a
  /// neighbourhood.
  final bool showDistance;
  final VoidCallback onOpen;
  final ValueChanged<Booking> onMessage;
  final ValueChanged<Booking> onCall;

  /// Later bookings get a line each, up to this many; the rest are
  /// counted.
  static const linesShown = 2;

  /// The main row's height on the design frame.
  static double get mainHeight => 76.w;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = bookings.first;
    final later = bookings.skip(1).take(linesShown).toList();
    final more = bookings.length - 1 - later.length;

    // One stop for screen readers with the whole day, then the message and
    // call buttons, which keep their own.
    return Pressable(
      onTap: onOpen,
      pressedScale: 0.99,
      focusRadius: AppRadius.lgAll,
      child: Semantics(
        label: _describe(first, later, more),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MainRow(
                booking: first,
                now: now,
                showDistance: showDistance,
                onMessage: () => onMessage(first),
                onCall: () => onCall(first),
              ),
              for (final booking in later) ...[
                Divider(height: 1, thickness: 1, color: c.border),
                _LaterLine(
                  time: Schedule.time(booking.scheduledAt),
                  what: [booking.serviceName, booking.area],
                ),
              ],
              if (more > 0) ...[
                Divider(height: 1, thickness: 1, color: c.border),
                _LaterLine(what: ['+$more more today']),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _describe(Booking first, List<Booking> later, int more) {
    final where = [
      first.area,
      if (first.landmark case final landmark?) landmark,
      if (showDistance && first.distanceKm != null)
        ArtisanFormat.spokenKm(first.distanceKm!),
    ].join(', ');
    final client = ArtisanFormat.shortName(first.counterpartName);
    return [
      'Next job, ${Schedule.time(first.scheduledAt)}, '
          '${ArtisanFormat.spokenStartsIn(first.scheduledAt, now)}: '
          '${first.serviceName} for $client, $where.',
      for (final booking in later)
        'Also today, ${Schedule.time(booking.scheduledAt)}: '
            '${booking.serviceName} in ${booking.area}.',
      if (more > 0) '$more more today.',
    ].join(' ');
  }
}

/// The next booking: time and countdown | what, who, where | message, call.
class _MainRow extends StatelessWidget {
  const _MainRow({
    required this.booking,
    required this.now,
    required this.showDistance,
    required this.onMessage,
    required this.onCall,
  });

  final Booking booking;
  final DateTime now;
  final bool showDistance;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final start = booking.scheduledAt;
    final untilStart = start.difference(now);
    final countdownColor = untilStart <= Duration.zero
        ? c.success
        : untilStart <= _soon
            ? c.warning
            : c.textSecondary;
    final secondary = AppText.bodySmall.copyWith(color: c.textSecondary);
    final client = ArtisanFormat.shortName(booking.counterpartName);
    final distance = booking.distanceKm;
    final findIt = [
      if (booking.landmark case final landmark? when landmark.isNotEmpty)
        '${landmark[0].toUpperCase()}${landmark.substring(1)}',
      if (showDistance && distance != null) ArtisanFormat.km(distance),
    ];

    // Message and call sit at the top right, beside the first two lines,
    // so the line saying how to find the place runs the full width.
    final besideActions =
        EdgeInsetsDirectional.only(end: _actionsWidth + AppSpace.s4);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: ArtisanTodayCard.mainHeight),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.w, 12.w, 10.w),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(
                    width: _timeColumn(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Schedule.time(start),
                          maxLines: 1,
                          style: AppText.titleSmall.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          ArtisanFormat.startsIn(start, now),
                          maxLines: 1,
                          style: AppText.caption.copyWith(
                            color: countdownColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Container(width: 1, height: 40.w, color: c.border),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: besideActions,
                          child: Text(
                            booking.serviceName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.titleSmall.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Padding(
                          padding: besideActions,
                          child: ArtisanMetaLine(
                            style: secondary,
                            facts: [
                              TextSpan(text: client),
                              TextSpan(text: booking.area),
                            ],
                          ),
                        ),
                        // How to find the place, distance included, is
                        // never cut short.
                        if (findIt.isNotEmpty)
                          ArtisanMetaLine(
                            style: secondary,
                            facts: [
                              for (final fact in findIt) TextSpan(text: fact),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Touch areas reach the card's edge; the circles sit 10 in.
          PositionedDirectional(
            top: 10.w - (AppSize.minTapTarget - AppSize.buttonSmall) / 2 + 1,
            end: 4.w,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CircleAction(
                  icon: IconsaxPlusLinear.message,
                  semanticLabel: 'Message $client',
                  onTap: onMessage,
                ),
                _CircleAction(
                  icon: IconsaxPlusLinear.call,
                  semanticLabel: 'Call $client',
                  onTap: onCall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A later booking, or how many more there are, in one 36pt line whose
/// time lines up under the first booking's.
class _LaterLine extends StatelessWidget {
  const _LaterLine({required this.what, this.time});

  final String? time;

  /// What and where, as facts: "Changeover switch repair · Jabi".
  final List<String> what;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 36.w),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 6.w, 12.w, 6.w),
          child: Row(
            children: [
              SizedBox(
                width: _timeColumn(context),
                child: time == null
                    ? null
                    : Text(
                        time!,
                        maxLines: 1,
                        style: AppText.bodySmall.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              SizedBox(width: _afterTime),
              Expanded(
                child: ArtisanMetaLine(
                  style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  facts: [for (final fact in what) TextSpan(text: fact)],
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
      ),
    );
  }
}

/// A 36pt round icon button in a 48pt touch area, for message and call.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      pressedScale: 0.92,
      focusRadius: AppRadius.pillAll,
      focusOffset: 0,
      child: SizedBox.square(
        dimension: AppSize.minTapTarget,
        child: Center(
          child: Container(
            width: AppSize.buttonSmall,
            height: AppSize.buttonSmall,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18.w, color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// "Nothing booked today", as one quiet 44pt line, with the next booking
/// on a later day when there is one.
class ArtisanNothingToday extends StatelessWidget {
  const ArtisanNothingToday({super.key, this.next});

  /// The next booking, on a later day.
  final Booking? next;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final upcoming = next;
    final when = upcoming == null
        ? null
        : 'Next: ${Schedule.dayAndTime(upcoming.scheduledAt)}';
    return Semantics(
      label: when == null
          ? 'Nothing booked today'
          : 'Nothing booked today. ${when.replaceFirst(':', ',')}',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: 44.w),
        // In the today card's place, so its corners, and the inset of what
        // it shows (12pt inside a 1pt border).
        padding: EdgeInsets.symmetric(
          horizontal: 12.w + 1,
          vertical: AppSpace.s8,
        ),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Icon(
              IconsaxPlusLinear.calendar_2,
              size: AppSize.iconSmall,
              color: c.textTertiary,
            ),
            SizedBox(width: AppSpace.s8),
            Expanded(
              child: ArtisanMetaLine(
                style: AppText.bodySmall.copyWith(color: c.textSecondary),
                facts: [
                  const TextSpan(text: 'Nothing booked today'),
                  if (when != null)
                    TextSpan(
                      text: when.replaceAll(' ', '\u00A0'),
                      style: TextStyle(color: c.textTertiary),
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

/// A placeholder in the shape of [ArtisanTodayCard] with one booking.
/// Place it inside a `SkeletonPulse`.
class ArtisanTodayCardSkeleton extends StatelessWidget {
  const ArtisanTodayCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double width, double height) =>
        SkeletonBox(width: width, height: height);
    return Container(
      constraints: BoxConstraints(minHeight: ArtisanTodayCard.mainHeight),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: c.border),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.w, 12.w, 10.w),
            child: Row(
              children: [
                SizedBox(
                  width: _timeColumn(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      bar(52.w, 13.w),
                      SizedBox(height: 8.w),
                      bar(40.w, 10.w),
                    ],
                  ),
                ),
                SizedBox(width: 10.w),
                Container(width: 1, height: 40.w, color: c.border),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 3.w),
                      bar(96.w, 13.w),
                      SizedBox(height: 9.w),
                      bar(120.w, 10.w),
                      SizedBox(height: 8.w),
                      bar(150.w, 10.w),
                      SizedBox(height: 4.w),
                    ],
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 10.w - (AppSize.minTapTarget - AppSize.buttonSmall) / 2 + 1,
            end: 4.w,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 2; i++)
                  SizedBox.square(
                    dimension: AppSize.minTapTarget,
                    child: Center(
                      child: SkeletonBox(
                        width: AppSize.buttonSmall,
                        height: AppSize.buttonSmall,
                        radius: AppRadius.pill,
                      ),
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
