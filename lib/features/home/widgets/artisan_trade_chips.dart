import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';

/// Which open jobs a list shows: the artisan's own trades, every trade, or
/// one.
@immutable
class ArtisanJobFilter {
  const ArtisanJobFilter._({this.isMine = false, this.tradeId});

  /// Jobs in one trade.
  const ArtisanJobFilter.trade(String id) : this._(tradeId: id);

  /// Jobs in every trade.
  static const all = ArtisanJobFilter._();

  /// Jobs in the trades on the artisan's account.
  static const myTrades = ArtisanJobFilter._(isMine: true);

  final bool isMine;

  /// The one trade, or null for [all] and [myTrades].
  final String? tradeId;

  @override
  bool operator ==(Object other) =>
      other is ArtisanJobFilter &&
      other.isMine == isMine &&
      other.tradeId == tradeId;

  @override
  int get hashCode => Object.hash(isMine, tradeId);
}

/// Trades to filter jobs by, in a 32pt chip row that scrolls edge to edge:
/// "My trades" for signed-in artisans, then "All", then each trade in the
/// order given. Place it full width; it pads itself to the gutter.
class ArtisanTradeChips extends StatelessWidget {
  const ArtisanTradeChips({
    super.key,
    required this.trades,
    required this.selected,
    required this.onSelected,
    this.showMyTrades = false,
  });

  final List<ServiceCategory> trades;
  final ArtisanJobFilter selected;
  final ValueChanged<ArtisanJobFilter> onSelected;

  /// Offer "My trades": the artisan has trades on their account.
  final bool showMyTrades;

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (showMyTrades)
        AppChip(
          label: 'My trades',
          icon: IconsaxPlusLinear.user_tick,
          selected: selected == ArtisanJobFilter.myTrades,
          singleChoice: true,
          onTap: () => onSelected(ArtisanJobFilter.myTrades),
        ),
      AppChip(
        label: 'All',
        icon: IconsaxPlusLinear.category,
        selected: selected == ArtisanJobFilter.all,
        singleChoice: true,
        onTap: () => onSelected(ArtisanJobFilter.all),
      ),
      for (final trade in trades)
        AppChip(
          label: trade.name,
          icon: CategoryIcons.of(trade.iconKey),
          selected: selected.tradeId == trade.id,
          singleChoice: true,
          onTap: () => onSelected(ArtisanJobFilter.trade(trade.id)),
        ),
    ];
    return SizedBox(
      height: AppSize.minTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        itemCount: chips.length,
        separatorBuilder: (context, index) => SizedBox(width: AppSpace.s8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }
}

/// A placeholder in the shape of [ArtisanTradeChips]. Place it inside a
/// `SkeletonPulse`.
class ArtisanTradeChipsSkeleton extends StatelessWidget {
  const ArtisanTradeChipsSkeleton({super.key});

  /// Roughly the widths of the first few chips.
  static const _widths = [104.0, 48.0, 112.0, 100.0, 96.0];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSize.minTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        itemCount: _widths.length,
        separatorBuilder: (context, index) => SizedBox(width: AppSpace.s8),
        // Chips keep their height at every screen size, as AppChip does.
        itemBuilder: (context, index) => Center(
          child: SkeletonBox(
            width: _widths[index],
            height: AppChip.height,
            radius: AppRadius.pill,
          ),
        ),
      ),
    );
  }
}
