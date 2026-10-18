import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Whether clients can book the artisan now: available, busy for a while,
/// or off. Returns the new state, or null when nothing changed.
Future<AvailabilityStatus?> showAvailabilitySheet(BuildContext context,
    {required ArtisanDashboard current}) {
  return showModalBottomSheet<AvailabilityStatus>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => _AvailabilityBody(current: current),
  );
}

class _AvailabilityBody extends StatefulWidget {
  const _AvailabilityBody({required this.current});

  final ArtisanDashboard current;

  @override
  State<_AvailabilityBody> createState() => _AvailabilityBodyState();
}

class _AvailabilityBodyState extends State<_AvailabilityBody> {
  bool _saving = false;

  Future<void> _set(bool available,
      {DateTime? until, required AvailabilityStatus result}) async {
    setState(() => _saving = true);
    await context
        .read<ArtisanDashboardRepository>()
        .setAvailability(available, busyUntil: until);
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 20);
    final status = widget.current.availability;
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Can clients book you now?', style: AppText.headline),
            SizedBox(height: 6.w),
            Text(
              'Requests only reach you while you are available. Jobs you already accepted stay on.',
              style: AppText.body.copyWith(color: c.textSecondary),
            ),
            SizedBox(height: 16.w),
            SelectionCard(
              icon: IconsaxPlusLinear.tick_circle,
              title: 'Available',
              subtitle: 'Get booking requests now',
              selected: status == AvailabilityStatus.available,
              onTap: _saving
                  ? () {}
                  : () => _set(true, result: AvailabilityStatus.available),
            ),
            SizedBox(height: 8.w),
            Text('Busy for a while',
                style: AppText.labelSmall.copyWith(color: c.textSecondary)),
            SizedBox(height: 4.w),
            Wrap(
              spacing: 8.w,
              children: [
                for (final (label, until) in [
                  ('1 hour', now.add(const Duration(hours: 1))),
                  ('2 hours', now.add(const Duration(hours: 2))),
                  if (endOfDay.isAfter(now.add(const Duration(hours: 2))))
                    ('Until ${Schedule.time(endOfDay)}', endOfDay),
                ])
                  PromptChip(
                    label: label,
                    icon: IconsaxPlusLinear.clock,
                    onTap: _saving
                        ? null
                        : () => _set(false,
                            until: until, result: AvailabilityStatus.busy),
                  ),
              ],
            ),
            SizedBox(height: 8.w),
            SelectionCard(
              icon: IconsaxPlusLinear.moon,
              title: 'Off',
              subtitle: 'No requests until you switch back on',
              selected: status == AvailabilityStatus.off,
              onTap: _saving
                  ? () {}
                  : () => _set(false, result: AvailabilityStatus.off),
            ),
          ],
        ),
      ),
    );
  }
}
