import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';

/// A one-line list item: rows are at least this tall.
double get _rowHeight => math.max(AppSize.minTapTarget, 48.w);

final _thousands = NumberFormat('#,##0', 'en_US');

/// What common jobs usually cost, one line each, so a client knows a fair
/// price before anyone quotes. Tapping a job shows the artisans who do it.
class ClientPriceGuide extends StatelessWidget {
  const ClientPriceGuide({
    super.key,
    required this.items,
    required this.onTap,
    this.tradeNames = const {},
  });

  /// Shows the first [shown].
  final List<PriceGuideItem> items;
  final ValueChanged<PriceGuideItem> onTap;

  /// Who does each trade ("AC technicians"), by category id, for screen
  /// readers: "Show AC technicians".
  final Map<String, String> tradeNames;

  static const shown = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = items.take(shown).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Text(
            'Updated ${DateFormat('MMM y').format(rows.first.updatedOn)}',
            style: AppText.caption.copyWith(color: c.textTertiary),
          ),
        ),
        SizedBox(height: AppSpace.s4),
        for (final (i, item) in rows.indexed)
          _PriceRow(
            item: item,
            who: tradeNames[item.categoryId] ?? 'artisans',
            divider: i < rows.length - 1,
            onTap: () => onTap(item),
          ),
      ],
    );
  }
}

/// "₦8k–12k". One naira sign: in Inter the dash meets a second sign's
/// crossbars, and "₦8k–₦12k" reads as one struck-through line.
String _compactRange(int min, int max) => '₦${_k(min)}–${_k(max)}';

/// 8000 as "8k", 7500 as "7.5k", 800 as "800".
String _k(int amount) {
  if (amount < 1000) return '$amount';
  final thousands = amount / 1000;
  final text = thousands == thousands.roundToDouble()
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${text}k';
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.item,
    required this.who,
    required this.divider,
    required this.onTap,
  });

  final PriceGuideItem item;
  final String who;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spoken = '${item.problem}, usually '
        '${_thousands.format(item.minPrice)} to '
        '${_thousands.format(item.maxPrice)} naira. Show $who';
    return Stack(
      children: [
        Pressable(
          onTap: onTap,
          semanticLabel: spoken,
          focusOffset: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _rowHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpace.gutter,
                vertical: AppSpace.s12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.problem,
                      style: AppText.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                  SizedBox(width: AppSpace.s12),
                  Text(
                    _compactRange(item.minPrice, item.maxPrice),
                    maxLines: 1,
                    softWrap: false,
                    style: AppText.labelSmall.copyWith(color: c.textPrimary),
                  ),
                  SizedBox(width: AppSpace.s4),
                  Icon(
                    IconsaxPlusLinear.arrow_right_3,
                    size: 14.w,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (divider)
          PositionedDirectional(
            start: AppSpace.gutter,
            end: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(height: 1, color: c.border),
            ),
          ),
      ],
    );
  }
}

/// Loading placeholder shaped like [ClientPriceGuide].
class ClientPriceGuideSkeleton extends StatelessWidget {
  const ClientPriceGuideSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 3.w),
              child: SkeletonBox(width: 104.w, height: 10.w),
            ),
          ),
        ),
        SizedBox(height: AppSpace.s4),
        for (var i = 0; i < ClientPriceGuide.shown; i++)
          Container(
            height: _rowHeight,
            // The hairline starts at the gutter, as the rows' do.
            margin: EdgeInsetsDirectional.only(start: AppSpace.gutter),
            padding: EdgeInsetsDirectional.only(end: AppSpace.gutter),
            decoration: BoxDecoration(
              border: i < ClientPriceGuide.shown - 1
                  ? Border(bottom: BorderSide(color: c.border))
                  : null,
            ),
            child: Row(
              children: [
                SkeletonBox(width: (180 - i * 16).w, height: 14.w),
                const Spacer(),
                SkeletonBox(width: 72.w, height: 14.w),
              ],
            ),
          ),
      ],
    );
  }
}
