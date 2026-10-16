import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';

/// The filters for the client Home's list, in one row that scrolls edge to
/// edge: "Free now", which works with any trade, then "All" and each trade,
/// of which one is on. They change the list in place.
class ClientFilterChips extends StatefulWidget {
  const ClientFilterChips({
    super.key,
    required this.categories,
    required this.loading,
    required this.categoryId,
    required this.freeNow,
    required this.onFreeNowChanged,
    required this.onCategoryChanged,
  });

  /// The trades, or null until they load. If they fail to, the row keeps
  /// "Free now" and "All", and the screen says so under it.
  final List<ServiceCategory>? categories;

  /// The trades are loading: placeholders stand in for their chips.
  final bool loading;

  /// The trade the list shows; null for all of them.
  final String? categoryId;
  final bool freeNow;
  final ValueChanged<bool> onFreeNowChanged;
  final ValueChanged<String?> onCategoryChanged;

  /// The row's height: a chip's 48pt touch area, or the chip itself once
  /// large text makes it taller.
  static double heightFor(TextScaler scaler) {
    final label = AppText.labelSmall;
    final line = scaler.scale(label.fontSize!) * label.height!;
    // The chip's padding and border around its label.
    final chip = line + AppSpace.s4 * 2 + 2;
    return math.max(AppSize.minTapTarget, chip.ceilToDouble());
  }

  @override
  State<ClientFilterChips> createState() => _ClientFilterChipsState();
}

class _ClientFilterChipsState extends State<ClientFilterChips> {
  final _scroll = ScrollController();

  /// The trade chips, by category id (null for "All"), so the row can
  /// bring the one that's on into view.
  final _keys = <String?, GlobalKey>{};

  GlobalKey _keyFor(String? id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void didUpdateWidget(ClientFilterChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chosen elsewhere (a price row), or a chip only peeking at the edge.
    if (oldWidget.categoryId != widget.categoryId) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(widget.categoryId),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the row just enough to show the chip for [id] whole, inside
  /// the gutters.
  void _reveal(String? id) {
    if (!mounted || !_scroll.hasClients) return;
    final chip = _keys[id]?.currentContext?.findRenderObject();
    final row = context.findRenderObject();
    if (chip is! RenderBox || row is! RenderBox || !chip.attached) return;
    final left = chip.localToGlobal(Offset.zero, ancestor: row).dx;
    final right = left + chip.size.width;
    final start = AppSpace.gutter;
    final end = row.size.width - AppSpace.gutter;
    final double by;
    if (left < start) {
      by = left - start;
    } else if (right > end) {
      by = right - end;
    } else {
      return;
    }
    final position = _scroll.position;
    final target = (position.pixels + by).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final duration = context.motion(AppMotion.base);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: duration, curve: AppMotion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = widget.categories;
    final chips = <Widget>[
      AppChip(
        label: 'Free now',
        dotColor: c.online,
        selected: widget.freeNow,
        onTap: () => widget.onFreeNowChanged(!widget.freeNow),
      ),
      AppChip(
        key: _keyFor(null),
        label: 'All',
        icon: IconsaxPlusLinear.category,
        selected: widget.categoryId == null,
        singleChoice: true,
        onTap: () => widget.onCategoryChanged(null),
      ),
      if (categories != null)
        for (final category in categories)
          AppChip(
            key: _keyFor(category.id),
            label: category.name,
            icon: CategoryIcons.of(category.iconKey),
            selected: widget.categoryId == category.id,
            singleChoice: true,
            onTap: () => widget.onCategoryChanged(category.id),
          )
      else if (widget.loading)
        const SkeletonPulse(child: _ChipSkeletons()),
    ];
    return SizedBox(
      height: ClientFilterChips.heightFor(MediaQuery.textScalerOf(context)),
      // Every chip is built, so any of them can be scrolled to.
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) SizedBox(width: AppSpace.s8),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Where the trade chips would be, while they load.
class _ChipSkeletons extends StatelessWidget {
  const _ChipSkeletons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, width) in [104.0, 96.0, 100.0, 92.0].indexed) ...[
          if (i > 0) SizedBox(width: AppSpace.s8),
          SkeletonBox(
            width: width.w,
            height: AppChip.height,
            radius: AppRadius.pill,
          ),
        ],
      ],
    );
  }
}
