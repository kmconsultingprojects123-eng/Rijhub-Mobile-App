import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import '../../location/area_pill.dart';
import 'artisan_format.dart';

/// The pills' visible height. Their touch area is 48.
double get _pillHeight => 40.w;

/// The top of a signed-in artisan's Home, 56pt tall: whether clients can
/// book them on the left; the week's earnings and notifications on the
/// right. No avatar or greeting: the Profile tab holds who they are.
class ArtisanTopBar extends StatelessWidget {
  const ArtisanTopBar({
    super.key,
    required this.availability,
    required this.onNotifications,
    this.wallet,
  });

  /// An [ArtisanAvailabilityPill], or its skeleton while it loads.
  final Widget? availability;

  /// An [ArtisanWalletPill], or nothing until there are earnings.
  final Widget? wallet;
  final VoidCallback onNotifications;

  /// The bar's height on the design frame.
  static double get height => 56.w;

  @override
  Widget build(BuildContext context) {
    // The bell's glyph lines up with the gutter and its touch area reaches
    // past it, as on the client's Home.
    final bellInset = (AppSize.minTapTarget - AppSize.icon) / 2;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: AppSpace.gutter,
          end: math.max(0, AppSpace.gutter - bellInset),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              // Availability is the control, so it keeps all its words
              // ("Busy till 5:30 PM"); the wallet makes room for it.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    0,
                    constraints.maxWidth - AppSize.minTapTarget,
                  ),
                ),
                child: availability ?? const SizedBox.shrink(),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: AppSpace.s8),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: wallet ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              AppIconButton(
                icon: IconsaxPlusLinear.notification,
                // No dot until there is something to read.
                semanticLabel: 'Notifications',
                onPressed: onNotifications,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of a guest artisan's Home, 48pt tall: the area jobs are shown
/// for, and a way in for people who already have an account.
class ArtisanGuestTopBar extends StatelessWidget {
  const ArtisanGuestTopBar({super.key, required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Row(
        children: [
          const Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AreaPill(),
            ),
          ),
          SizedBox(width: AppSpace.s12),
          Pressable(
            onTap: onSignIn,
            semanticLabel: 'Sign in',
            focusRadius: AppRadius.mdAll,
            focusOffset: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSize.minTapTarget,
                minHeight: AppSize.minTapTarget,
              ),
              child: Padding(
                // The words line up with the gutter; the touch area
                // reaches past them on the left.
                padding: EdgeInsetsDirectional.only(start: AppSpace.s8),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  widthFactor: 1,
                  child: Text(
                    'Sign in',
                    style: AppText.labelSmall.copyWith(color: c.brandText),
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

/// Whether clients can book the artisan, as a pill that is also the
/// control: tapping it opens the availability sheet.
class ArtisanAvailabilityPill extends StatelessWidget {
  const ArtisanAvailabilityPill({
    super.key,
    required this.status,
    required this.onTap,
    this.busyUntil,
  });

  final AvailabilityStatus status;

  /// When a busy spell ends. Only read while [status] is busy.
  final DateTime? busyUntil;
  final VoidCallback onTap;

  /// The pill's words: "Available", "Busy till 4:30 PM" or "Off".
  static String label(AvailabilityStatus status, DateTime? busyUntil) =>
      switch (status) {
        AvailabilityStatus.available => 'Available',
        AvailabilityStatus.busy when busyUntil != null =>
          'Busy till ${ArtisanFormat.clock(busyUntil)}',
        AvailabilityStatus.busy => 'Busy',
        AvailabilityStatus.off => 'Off',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color fill, Color ink, Color? edge) = switch (status) {
      AvailabilityStatus.available => (c.successSubtle, c.success, null),
      AvailabilityStatus.busy => (c.warningSubtle, c.warning, null),
      AvailabilityStatus.off => (c.surface, c.textSecondary, c.borderStrong),
    };
    final until = busyUntil;
    final text = label(status, until);
    final spoken = switch (status) {
      AvailabilityStatus.available => 'Available: clients can book you',
      AvailabilityStatus.busy when until != null =>
        'Busy until ${ArtisanFormat.clock(until)}',
      AvailabilityStatus.busy => 'Busy',
      AvailabilityStatus.off => "Off: clients can't book you",
    };
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Availability. $spoken. Change',
      focusRadius: AppRadius.pillAll,
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.base),
            curve: AppMotion.standard,
            constraints: BoxConstraints(minHeight: _pillHeight),
            padding: EdgeInsetsDirectional.only(
              start: AppSpace.s12,
              end: AppSpace.s8,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: edge ?? fill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(status: status),
                SizedBox(width: AppSpace.s8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.labelSmall.copyWith(color: ink),
                  ),
                ),
                SizedBox(width: AppSpace.s4),
                Icon(
                  IconsaxPlusLinear.arrow_down,
                  size: AppSize.iconSmall,
                  color: ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The availability dot: filled green when available, amber when busy,
/// hollow grey when off, so the state has a shape as well as a colour.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AvailabilityStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = AppSpace.s8;
    return switch (status) {
      AvailabilityStatus.off => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.textTertiary, width: 1.5),
          ),
        ),
      _ => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                status == AvailabilityStatus.available ? c.online : c.warning,
          ),
        ),
    };
  }
}

/// This week's earnings, as a pill. Tapping it hides the amount, for
/// opening the app in a client's home, and shows it again.
///
/// Where the room it is given is short (large text on a small phone), it
/// drops its icon, then steps aside altogether rather than cut the amount.
class ArtisanWalletPill extends StatelessWidget {
  const ArtisanWalletPill({
    super.key,
    required this.amount,
    required this.hidden,
    required this.onToggle,
  });

  /// Naira earned this week.
  final int amount;
  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = Naira.format(amount);
    final text = hidden ? '₦ •••••' : shown;
    final style = AppText.labelSmall.copyWith(color: c.textPrimary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final textWidth = painter.width.ceilToDouble();
        painter.dispose();
        final padding = 2 * AppSpace.s12;
        final icon = AppSize.iconSmall + AppSpace.s6;
        if (constraints.maxWidth < padding + textWidth) {
          return const SizedBox.shrink();
        }
        final withIcon = constraints.maxWidth >= padding + icon + textWidth;
        return Pressable(
          onTap: onToggle,
          semanticLabel: hidden
              ? 'Earned this week: hidden. Show the amount'
              : 'Earned this week: $shown. Hide the amount',
          focusRadius: AppRadius.pillAll,
          focusOffset: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSize.minTapTarget,
            ),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                constraints: BoxConstraints(minHeight: _pillHeight),
                padding: EdgeInsets.symmetric(horizontal: AppSpace.s12),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: AppRadius.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (withIcon) ...[
                      Icon(
                        IconsaxPlusLinear.empty_wallet,
                        size: AppSize.iconSmall,
                        color: c.textSecondary,
                      ),
                      SizedBox(width: AppSpace.s6),
                    ],
                    Text(text, maxLines: 1, softWrap: false, style: style),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pill-shaped placeholder for the top bar's pills while the dashboard
/// loads. Place it inside a `SkeletonPulse`.
class ArtisanPillSkeleton extends StatelessWidget {
  const ArtisanPillSkeleton({super.key, required this.width});

  /// On the design frame; scales with the screen.
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSize.minTapTarget,
      child: Center(
        widthFactor: 1,
        child: SkeletonBox(
          width: width.w,
          height: _pillHeight,
          radius: AppRadius.pill,
        ),
      ),
    );
  }
}
