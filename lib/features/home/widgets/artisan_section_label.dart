import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

/// A light section label: a 24pt row of small capitals ("TODAY · THU 16
/// OCT"), with an optional link on the right ("Schedule").
///
/// Like [SectionHeader], the link takes taps in a 48pt band around the row,
/// which needs parents that pass taps on: a `Column`, or `SliverList.list`
/// with `addRepaintBoundaries: false`.
class ArtisanSectionLabel extends StatelessWidget {
  const ArtisanSectionLabel({
    super.key,
    required this.text,
    required this.semanticLabel,
    this.actionLabel,
    this.actionSemanticLabel,
    this.onAction,
  });

  /// Shown in capitals.
  final String text;

  /// What screen readers say, in words: "Today, Thursday 16 October".
  final String semanticLabel;
  final String? actionLabel;

  /// What screen readers say for the link, when its label needs context.
  final String? actionSemanticLabel;
  final VoidCallback? onAction;

  /// The row's height. Content sits 8 below it.
  static double get height => AppSpace.s24;

  /// Small capitals: caption at 600, a little apart so they stay legible.
  static TextStyle style(BuildContext context) => AppText.caption.copyWith(
        color: context.colors.textTertiary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      );

  @override
  Widget build(BuildContext context) {
    return _LinkRow(
      heading: Semantics(
        header: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style(context),
        ),
      ),
      actionLabel: actionLabel,
      actionSemanticLabel: actionSemanticLabel,
      onAction: onAction,
    );
  }
}

/// A section title with a "See all" link, for a section whose content
/// starts right under it, such as a row of chips. The link's 48pt touch
/// band reaches up into the gap above, [reachAbove] at most, rather than
/// down into what follows.
class ArtisanSectionHeader extends StatelessWidget {
  const ArtisanSectionHeader({
    super.key,
    required this.title,
    required this.reachAbove,
    this.actionLabel,
    this.onAction,
  });

  final String title;

  /// The free space above the header that the link's band may use.
  final double reachAbove;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _LinkRow(
      heading: Semantics(
        header: true,
        child: Text(
          title,
          style: AppText.title.copyWith(color: context.colors.textPrimary),
        ),
      ),
      actionLabel: actionLabel,
      actionSemanticLabel: actionLabel == null ? null : '$actionLabel, $title',
      onAction: onAction,
      reachAbove: reachAbove,
    );
  }
}

/// A 24pt row: a heading, and an optional link whose touch band makes it
/// 48pt tall, centred on the row unless [reachAbove] says how far up it
/// may go.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.heading,
    required this.actionLabel,
    required this.actionSemanticLabel,
    required this.onAction,
    this.reachAbove,
  });

  final Widget heading;
  final String? actionLabel;
  final String? actionSemanticLabel;
  final VoidCallback? onAction;
  final double? reachAbove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Grows past 24 only for the largest text sizes.
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppSpace.s24),
      child: Row(
        children: [
          Expanded(child: heading),
          if (actionLabel case final action?)
            _TapTargetSemantics(
              reachAbove: reachAbove,
              child: Pressable(
                onTap: onAction,
                semanticLabel: actionSemanticLabel ?? action,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: AppSpace.s12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      action,
                      style: AppText.labelSmall.copyWith(color: c.brandText),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return actionLabel == null
        ? row
        : _TouchBand(reachAbove: reachAbove, child: row);
  }
}

/// How far above and below a [height]-tall box a band reaches to make it
/// 48pt tall: evenly, or up to [above] above and the rest below.
(double, double) _reach(double height, double? above) {
  final total = math.max(0.0, AppSize.minTapTarget - height);
  if (above == null) return (total / 2, total / 2);
  final up = math.min(total, math.max(0.0, above));
  return (up, total - up);
}

/// Lays out its child unchanged but takes taps in a band at least 48pt
/// tall around it, passing each one to the child at the same horizontal
/// position on its middle line.
class _TouchBand extends SingleChildRenderObjectWidget {
  const _TouchBand({this.reachAbove, required Widget super.child});

  final double? reachAbove;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTouchBand(reachAbove);

  @override
  void updateRenderObject(BuildContext context, _RenderTouchBand renderObject) {
    renderObject.reachAbove = reachAbove;
  }
}

class _RenderTouchBand extends RenderProxyBox {
  _RenderTouchBand(this.reachAbove);

  double? reachAbove;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final (up, down) = _reach(size.height, reachAbove);
    final inBand = position.dx >= 0 &&
        position.dx < size.width &&
        position.dy >= -up &&
        position.dy < size.height + down;
    if (!inBand) return false;
    return super.hitTest(
      result,
      position: Offset(position.dx, size.height / 2),
    );
  }
}

/// Merges its child's semantics into one node at least 48pt tall, over the
/// same band a finger has, so screen readers find the same target.
class _TapTargetSemantics extends SingleChildRenderObjectWidget {
  const _TapTargetSemantics({this.reachAbove, required Widget super.child});

  final double? reachAbove;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapTargetSemantics(reachAbove);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTapTargetSemantics renderObject,
  ) {
    renderObject.reachAbove = reachAbove;
  }
}

class _RenderTapTargetSemantics extends RenderProxyBox {
  _RenderTapTargetSemantics(this._reachAbove);

  double? _reachAbove;

  set reachAbove(double? value) {
    if (value == _reachAbove) return;
    _reachAbove = value;
    markNeedsSemanticsUpdate();
  }

  @override
  Rect get semanticBounds {
    final (up, down) = _reach(size.height, _reachAbove);
    return Rect.fromLTRB(0, -up, size.width, size.height + down);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = true;
  }
}
