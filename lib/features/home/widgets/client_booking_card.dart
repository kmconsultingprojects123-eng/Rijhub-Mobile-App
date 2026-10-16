import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/images.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'client_meta_line.dart';

/// A two-line list item: the card is at least this tall.
double get _minHeight => 72.w;
double get _avatarSize => 40.w;
double get _padding => AppSpace.s12;

/// The round actions look this big; each takes taps in 48pt.
double get _actionSize => 36.w;

/// How far an action's touch area reaches past its circle.
double get _actionReach => (AppSize.minTapTarget - _actionSize) / 2;

/// The width the two actions take inside the card, from the first circle's
/// edge to the last's. Their touch areas meet between the circles.
double get _actionsWidth => _actionSize * 2 + _actionReach * 2;

/// The client's next booking, at the top of Home: who is coming and when,
/// whether it's confirmed and the code that starts the job, with chat and
/// call one tap away. Tapping the card opens Bookings.
class ClientBookingCard extends StatelessWidget {
  const ClientBookingCard({
    super.key,
    required this.booking,
    required this.onTap,
    required this.onMessage,
    required this.onCall,
  });

  final Booking booking;
  final VoidCallback onTap;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final who = booking.counterpartName;
    final firstName = who.split(' ').first;
    final now = DateTime.now();
    final (status, statusColor) = _status(booking.status, c);
    final code = _code;

    final card = Pressable(
      onTap: onTap,
      semanticLabel: [
        'Next booking: ${booking.serviceName} with $who, '
            '${_When.spoken(booking.scheduledAt, now)}',
        status,
        if (code != null) 'Start code ${code.split('').join(' ')}',
      ].join('. '),
      focusRadius: AppRadius.lgAll,
      child: Container(
        constraints: BoxConstraints(minHeight: _minHeight),
        padding: EdgeInsets.all(_padding),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            AppAvatar(
              name: who,
              image: imageFor(booking.counterpartPhoto),
              size: _avatarSize,
            ),
            SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "Emeka · Today, 2:30 PM": the face beside it says who,
                  // the name says it in words, and when is what the client
                  // checks this card for.
                  ClientMetaLine(
                    style: AppText.titleSmall.copyWith(color: c.textPrimary),
                    parts: [
                      TextSpan(text: firstName),
                      TextSpan(text: _When.short(booking.scheduledAt, now)),
                    ],
                  ),
                  SizedBox(height: AppSpace.s2),
                  // "● Confirmed · Code 4829"
                  ClientMetaLine(
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                    parts: [
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '●\u00A0',
                            style: TextStyle(color: statusColor),
                          ),
                          TextSpan(text: status),
                        ],
                      ),
                      if (code != null)
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Code\u00A0'),
                            TextSpan(
                              text: code,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Room for the actions, which sit over the card.
            SizedBox(width: AppSpace.s8 + _actionsWidth),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        card,
        // Over the card rather than inside it, so each is its own tap
        // target and its own stop for screen readers.
        PositionedDirectional(
          top: 0,
          bottom: 0,
          end: _padding - _actionReach,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CardAction(
                icon: IconsaxPlusLinear.message,
                semanticLabel: 'Message $firstName',
                onTap: onMessage,
              ),
              _CardAction(
                icon: IconsaxPlusLinear.call,
                semanticLabel: 'Call $firstName',
                onTap: onCall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The start code, while the job is still to start: the client gives it
  /// to the artisan on arrival.
  String? get _code => switch (booking.status) {
        BookingStatus.confirmed || BookingStatus.onTheWay => booking.startCode,
        _ => null,
      };
}

/// What the booking's dot and word say. Status colours only: crimson is
/// for actions, so a job under way is blue like one on its way.
(String, Color) _status(BookingStatus status, AppColors c) => switch (status) {
      BookingStatus.requested => ('Waiting to be confirmed', c.warning),
      BookingStatus.confirmed => ('Confirmed', c.success),
      BookingStatus.onTheWay => ('On the way', c.info),
      BookingStatus.inProgress => ('In progress', c.info),
      BookingStatus.completed => ('Done', c.textTertiary),
    };

/// When a booking is, as the card shows it and as screen readers say it.
abstract final class _When {
  /// Short enough to share a line with a first name: "Today, 2:30 PM",
  /// "Tomorrow, 9 AM", "Mon, 9 AM" within the week, else "26 Oct, 9 AM".
  /// The day and the time each hold together, so a narrow card breaks the
  /// line only after the comma.
  static String short(DateTime at, DateTime now) {
    final days = _days(now, at);
    final day = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      > 1 && < 7 => DateFormat('EEE').format(at),
      _ => DateFormat('d\u00A0MMM').format(at),
    };
    return '$day, ${_time(at)}';
  }

  /// "today at 2:30 PM", "Monday at 9 AM", "26 October at 9 AM".
  static String spoken(DateTime at, DateTime now) {
    final days = _days(now, at);
    final day = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      -1 => 'yesterday',
      > 1 && < 7 => DateFormat('EEEE').format(at),
      _ => DateFormat('d MMMM').format(at),
    };
    return '$day at ${_time(at).replaceAll('\u00A0', ' ')}';
  }

  /// "9 AM" on the hour, else "2:30 PM", as the artisan rows write it.
  static String _time(DateTime at) =>
      DateFormat(at.minute == 0 ? 'h\u00A0a' : 'h:mm\u00A0a').format(at);

  /// Calendar days from [from] to [to], so the hour of day doesn't matter.
  static int _days(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;
}

/// A round icon action on the card: 36pt to see, 48pt to tap.
class _CardAction extends StatelessWidget {
  const _CardAction({
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
      // The 48pt touch area already rings the circle.
      focusOffset: 0,
      child: SizedBox.square(
        dimension: AppSize.minTapTarget,
        child: Center(
          child: Container(
            width: _actionSize,
            height: _actionSize,
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

/// Loading placeholder shaped like [ClientBookingCard].
class ClientBookingCardSkeleton extends StatelessWidget {
  const ClientBookingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(minHeight: _minHeight),
      padding: EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SkeletonBox(
            width: _avatarSize,
            height: _avatarSize,
            radius: _avatarSize / 2,
          ),
          SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 136.w, height: 14.w),
                SizedBox(height: 10.w),
                SkeletonBox(width: 112.w, height: 12.w),
              ],
            ),
          ),
          SizedBox(width: AppSpace.s8),
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) SizedBox(width: _actionReach * 2),
            SkeletonBox(
              width: _actionSize,
              height: _actionSize,
              radius: _actionSize / 2,
            ),
          ],
        ],
      ),
    );
  }
}
