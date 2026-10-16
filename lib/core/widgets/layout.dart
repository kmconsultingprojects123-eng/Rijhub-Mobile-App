import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import 'app_button.dart';
import 'app_icon_button.dart';
import 'pressable.dart';

/// Title row for a content section, with an optional "See all" link.
///
/// The row is as tall as its title whether or not it has a link, so
/// sections keep the same rhythm when a link hides. The link still gets a
/// 48pt touch area: taps up to 11pt above and below the row reach it, which
/// the 32pt gap above a section and the 12pt gap below its title leave free.
/// Screen readers get the same 48pt target.
///
/// The band only works where the row's parents take taps outside it, as a
/// Column does. A list that puts each child in its own repaint boundary
/// (`SliverList.list` does by default) cuts it back to the row, so build
/// those with `addRepaintBoundaries: false`.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: AppText.title.copyWith(color: c.textPrimary),
            ),
          ),
        ),
        if (actionLabel != null)
          _TapTargetSemantics(
            child: Pressable(
              onTap: onAction,
              semanticLabel: '$actionLabel, $title',
              child: Padding(
                padding: EdgeInsets.only(left: AppSpace.s12),
                child: Text(
                  actionLabel!,
                  style: AppText.labelSmall.copyWith(color: c.brandText),
                ),
              ),
            ),
          ),
      ],
    );
    return actionLabel == null ? row : _TouchHeight(child: row);
  }
}

/// Reach above and below a [height]-tall box that makes it 48pt tall.
double _reachFor(double height) =>
    math.max(0.0, (AppSize.minTapTarget - height) / 2);

/// Lays out its child unchanged but takes taps in a band at least 48pt
/// tall around it, passing each one to the child at the same horizontal
/// position on its middle line.
class _TouchHeight extends SingleChildRenderObjectWidget {
  const _TouchHeight({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTouchHeight();
}

class _RenderTouchHeight extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final reach = _reachFor(size.height);
    final inBand = position.dx >= 0 &&
        position.dx < size.width &&
        position.dy >= -reach &&
        position.dy < size.height + reach;
    if (!inBand) return false;
    return super.hitTest(
      result,
      position: Offset(position.dx, size.height / 2),
    );
  }
}

/// Merges its child's semantics into one node that is at least 48pt tall,
/// centred on the child, so screen readers and accessibility checkers find
/// the same target a finger does.
class _TapTargetSemantics extends SingleChildRenderObjectWidget {
  const _TapTargetSemantics({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapTargetSemantics();
}

class _RenderTapTargetSemantics extends RenderProxyBox {
  @override
  Rect get semanticBounds {
    final reach = _reachFor(size.height);
    return Rect.fromLTRB(0, -reach, size.width, size.height + reach);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // Owning the node is what gives it these bounds.
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = true;
  }
}

/// A plain surface with a hairline border. Cards never use shadows.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
    this.borderColor,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Defaults to 16 on every side.
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Container(
      padding: padding ?? EdgeInsets.all(AppSpace.s16),
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: borderColor ?? c.border),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      focusRadius: AppRadius.lgAll,
      child: card,
    );
  }
}

/// Back button plus an optional step indicator, for flows with a few steps.
class FlowTopBar extends StatelessWidget {
  const FlowTopBar({
    super.key,
    this.onBack,
    this.step,
    this.totalSteps,
    this.trailing,
  });

  final VoidCallback? onBack;
  final int? step;
  final int? totalSteps;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final showSteps = step != null && totalSteps != null;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          AppIconButton(
            icon: IconsaxPlusLinear.arrow_left,
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            semanticLabel: 'Back',
          ),
          SizedBox(width: AppSpace.s8),
          if (showSteps)
            Expanded(child: StepProgress(step: step!, total: totalSteps!))
          else
            const Spacer(),
          SizedBox(width: AppSpace.s8),
          trailing ?? const SizedBox(width: AppSize.minTapTarget),
        ],
      ),
    );
  }
}

/// A segmented progress bar: "step 2 of 3".
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total});

  /// 1-based.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Step $step of $total',
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) SizedBox(width: AppSpace.s6),
            Expanded(
              child: AnimatedContainer(
                duration: context.motion(AppMotion.base),
                curve: AppMotion.standard,
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? c.brandStroke : c.border,
                  borderRadius: AppRadius.pillAll,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "──── or ────"
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'or'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: c.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.s12),
          child: Text(
            label,
            style: AppText.bodySmall.copyWith(color: c.textTertiary),
          ),
        ),
        Expanded(child: Divider(color: c.border)),
      ],
    );
  }
}

/// A friendly message for empty or not-yet-built areas.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.s32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: c.textSecondary),
          ),
          SizedBox(height: AppSpace.s20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(color: c.textPrimary),
          ),
          SizedBox(height: AppSpace.s8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textSecondary),
          ),
          if (action != null) ...[
            SizedBox(height: AppSpace.s24),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A section that failed to load, with a way to try again. Keeps the rest
/// of the screen usable.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.s16,
        AppSpace.s8,
        AppSpace.s8,
        AppSpace.s8,
      ),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          Icon(IconsaxPlusLinear.info_circle,
              size: AppSize.icon, color: c.textSecondary),
          SizedBox(width: AppSpace.s12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: AppText.bodySmall.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          AppButton(
            label: 'Try again',
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.small,
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A short, quiet message inside a section, for example when a list is
/// empty.
class InlineNote extends StatelessWidget {
  const InlineNote({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String message;
  final IconData? icon;

  /// Defaults to the secondary text colour. Set it when the icon is a
  /// status mark, such as the blue verified badge.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpace.s16),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSize.icon, color: iconColor ?? c.textSecondary),
            SizedBox(width: AppSpace.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // Hug the text, so the note never stretches to fill a
              // bounded space such as a sheet.
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AppText.titleSmall.copyWith(color: c.textPrimary)),
                SizedBox(height: AppSpace.s2),
                Text(message,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
