import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import '../utils/images.dart';
import 'app_avatar.dart';
import 'pressable.dart';

/// What is happening now, on a dark bar: a booking on its way, the next
/// job. The one dark surface on a screen, so it reads first.
class LiveBar extends StatelessWidget {
  const LiveBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.actionLabel,
    this.onTap,
    this.height = 60,
    this.floating = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// A face or a [TimeChip]. Without one, a green live dot.
  final Widget? leading;

  /// A round action (call, directions). Without one, [actionLabel] and a
  /// chevron.
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onTap;
  final double height;

  /// Over a map: with a shadow.
  final bool floating;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = c.onSurfaceStrong;
    final bar = Container(
      constraints: BoxConstraints(minHeight: height.w),
      padding:
          EdgeInsets.fromLTRB(leading == null ? 16.w : 10.w, 8.w, 10.w, 8.w),
      decoration: BoxDecoration(
        color: c.surfaceStrong,
        borderRadius: BorderRadius.circular(18.w),
        boxShadow: floating
            ? const [
                BoxShadow(
                    color: Color(0x38000000),
                    blurRadius: 18,
                    offset: Offset(0, 6))
              ]
            : null,
      ),
      child: Row(
        children: [
          leading ??
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  color: c.successOnStrong,
                  shape: BoxShape.circle,
                ),
              ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleSmall.copyWith(color: on),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2.w),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(
                      color: on.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 8.w),
          trailing ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionLabel != null)
                    Text(
                      actionLabel!,
                      style: AppText.labelSmall.copyWith(
                        color: on.withValues(alpha: 0.82),
                      ),
                    ),
                  Icon(
                    IconsaxPlusLinear.arrow_right_3,
                    size: 16.w,
                    color: on.withValues(alpha: 0.82),
                  ),
                  SizedBox(width: 4.w),
                ],
              ),
        ],
      ),
    );
    if (onTap == null) return bar;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$title. ${subtitle ?? ''}',
      focusRadius: BorderRadius.circular(18.w),
      child: bar,
    );
  }
}

/// A time on a dark bar: "2:30" over "PM".
class TimeChip extends StatelessWidget {
  const TimeChip({super.key, required this.time, required this.period});

  final String time;
  final String period;

  @override
  Widget build(BuildContext context) {
    final on = context.colors.onSurfaceStrong;
    return Container(
      width: 50.w,
      height: 44.w,
      decoration: BoxDecoration(
        color: on.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.w),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            time,
            style: AppText.titleSmall.copyWith(
              color: on,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            period,
            style: AppText.caption.copyWith(
              color: on.withValues(alpha: 0.6),
              fontSize: 10.sp,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round icon button on a dark bar or a map.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
    this.foreground,
    this.size = 40,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48.w,
          height: 48.w,
          child: Center(
            child: Container(
              width: size.w,
              height: size.w,
              decoration: BoxDecoration(
                color: background ?? c.brand,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: size.w * 0.45, color: foreground ?? c.onBrand),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small count in a crimson pill: "2".
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.muted = false});

  final int count;

  /// Grey, for counts that need no attention.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(minWidth: 20.w),
      height: 20.w,
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? c.surfaceMuted : c.brand,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: muted ? c.textSecondary : c.onBrand,
          height: 1,
        ),
      ),
    );
  }
}

/// A few faces overlapping: "these people, and more".
class FaceStack extends StatelessWidget {
  const FaceStack({super.key, required this.people, this.size = 28});

  /// Names with photos (or none, for initials).
  final List<(String, String?)> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = size.w;
    final step = s * 0.72;
    return SizedBox(
      width: s + 4 + (people.length - 1) * step,
      height: s + 4,
      child: Stack(
        children: [
          for (var i = 0; i < people.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration:
                    BoxDecoration(color: c.surface, shape: BoxShape.circle),
                child: AppAvatar(
                  name: people[i].$1,
                  image: imageFor(people[i].$2),
                  size: s,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Two to four tabs in a grey track, the picked one raised in white, each
/// with an optional count.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.counts = const {},
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Counts by tab index.
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 46.w,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(14.w),
        border: Border.all(color: c.border),
      ),
      // Stretched, so the picked tab's white fills the track's height, not
      // just its label's.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: counts[i] == null
                    ? labels[i]
                    : '${labels[i]}, ${counts[i]}',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: context.motion(AppMotion.fast),
                    decoration: i == selected
                        ? BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(10.w),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2)),
                            ],
                          )
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.labelSmall.copyWith(
                              color: i == selected
                                  ? c.textPrimary
                                  : c.textSecondary,
                            ),
                          ),
                        ),
                        if ((counts[i] ?? 0) > 0) ...[
                          SizedBox(width: 6.w),
                          CountBadge(counts[i]!, muted: i != selected),
                        ],
                      ],
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

/// A label and value on one line, for summaries: "Service fee · ₦600".
class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.strong = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = strong ? AppText.titleSmall : AppText.body;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.w),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18.w, color: c.textSecondary),
            SizedBox(width: 10.w),
          ],
          Expanded(
            child: Text(
              label,
              style: style.copyWith(
                color: strong ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}
