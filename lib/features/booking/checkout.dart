import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/payments.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../ask/ask_flow.dart';

/// Payment, through RijHub's payment partner. RijHub holds the money until
/// the client confirms the job is done.
///
/// With the API, booking opens Paystack's own checkout (card, bank transfer
/// or USSD), so this goes straight on. On sample data, this sheet stands in
/// for it with the same choices.
Future<bool> showCheckout(
  BuildContext context, {
  required int total,
  required String description,
}) async {
  if (context.read<PaymentGateway>().hosted) return true;
  final paid = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => _Checkout(total: total, description: description),
  );
  return paid ?? false;
}

enum _Method { card, transfer, ussd }

class _Checkout extends StatefulWidget {
  const _Checkout({required this.total, required this.description});

  final int total;
  final String description;

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  _Method _method = _Method.card;
  bool _paying = false;

  Future<void> _pay() async {
    setState(() => _paying = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(g, 0, g, g),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ${Naira.format(widget.total)}', style: AppText.headline),
            SizedBox(height: 4.w),
            Text(widget.description,
                style: AppText.body.copyWith(color: c.textSecondary)),
            SizedBox(height: 12.w),
            for (final (m, icon, title) in const [
              (_Method.card, IconsaxPlusLinear.card, 'Card'),
              (_Method.transfer, IconsaxPlusLinear.bank, 'Bank transfer'),
              (_Method.ussd, IconsaxPlusLinear.mobile, 'USSD'),
            ])
              Semantics(
                button: true,
                selected: _method == m,
                label: 'Pay by $title',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => setState(() => _method = m),
                  child: Container(
                    height: 56.w,
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.border))),
                    child: Row(
                      children: [
                        Icon(icon, size: 22.w, color: c.textPrimary),
                        SizedBox(width: 14.w),
                        Expanded(child: Text(title, style: AppText.bodyLarge)),
                        _method == m
                            ? Icon(IconsaxPlusBold.tick_circle,
                                size: 22.w, color: c.brandStroke)
                            : Container(
                                width: 20.w,
                                height: 20.w,
                                margin: EdgeInsets.all(1.w),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: c.borderStrong, width: 1.5)),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            SizedBox(height: 20.w),
            AppButton(
              label: 'Pay ${Naira.format(widget.total)}',
              isLoading: _paying,
              onPressed: _paying ? null : _pay,
            ),
            SizedBox(height: 10.w),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(IconsaxPlusLinear.lock_1,
                    size: 14.w, color: c.textTertiary),
                SizedBox(width: 6.w),
                Text('Secured by Paystack',
                    style: AppText.caption.copyWith(color: c.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks a day and a two-hour window, for "Pick a day".
Future<TimeWindow?> showDayPicker(BuildContext context) {
  return showModalBottomSheet<TimeWindow>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => const _DayPicker(),
  );
}

class _DayPicker extends StatefulWidget {
  const _DayPicker();

  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  final _today = DateTime.now();
  late DateTime _day = DateTime(_today.year, _today.month, _today.day + 1);
  int? _hour;

  static const _hours = [8, 10, 12, 14, 16, 18];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final days = [
      for (var i = 0; i < 14; i++)
        DateTime(_today.year, _today.month, _today.day + i),
    ];
    bool past(int hour) => DateTime(_day.year, _day.month, _day.day, hour)
        .isBefore(_today.add(const Duration(hours: 1)));
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.only(bottom: g),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: g),
              child: Text('Pick a day and time', style: AppText.headline),
            ),
            SizedBox(height: 16.w),
            SizedBox(
              height: 74.w,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: g),
                itemCount: days.length,
                separatorBuilder: (_, __) => SizedBox(width: 8.w),
                itemBuilder: (context, i) {
                  final d = days[i];
                  final on = d == _day;
                  const names = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun'
                  ];
                  return Semantics(
                    button: true,
                    selected: on,
                    label: Schedule.dayLabel(d),
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _day = d;
                        _hour = null;
                      }),
                      child: Container(
                        width: 56.w,
                        decoration: BoxDecoration(
                          color: on ? c.surfaceStrong : c.surface,
                          borderRadius: BorderRadius.circular(16.w),
                          border: on ? null : Border.all(color: c.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              i == 0 ? 'Today' : names[d.weekday - 1],
                              style: AppText.caption.copyWith(
                                color: on
                                    ? c.onSurfaceStrong.withValues(alpha: 0.7)
                                    : c.textTertiary,
                              ),
                            ),
                            SizedBox(height: 2.w),
                            Text(
                              '${d.day}',
                              style: AppText.title.copyWith(
                                  color:
                                      on ? c.onSurfaceStrong : c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 20.w),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: g),
              child: Wrap(
                spacing: 8.w,
                runSpacing: 8.w,
                children: [
                  for (final h in _hours)
                    PromptChip(
                      label: windowLabel(
                        TimeWindow(
                          start: DateTime(_day.year, _day.month, _day.day, h),
                          end: DateTime(_day.year, _day.month, _day.day, h + 2),
                        ),
                      ).split(', ').last,
                      selected: _hour == h,
                      onTap: past(h) ? null : () => setState(() => _hour = h),
                    ),
                ],
              ),
            ),
            SizedBox(height: 20.w),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: g),
              child: AppButton(
                label: 'Use this time',
                onPressed: _hour == null
                    ? null
                    : () {
                        final s =
                            DateTime(_day.year, _day.month, _day.day, _hour!);
                        Navigator.of(context).pop(TimeWindow(
                            start: s, end: s.add(const Duration(hours: 2))));
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
