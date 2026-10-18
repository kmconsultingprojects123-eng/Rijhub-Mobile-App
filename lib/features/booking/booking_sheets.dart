import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../ask/ask_flow.dart';
import 'checkout.dart';

/// Sheets for a booking: confirming, cancelling, moving it, starting it
/// with the client's code, and reviewing it.

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (context) => DoubleTapGuard(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            0,
            AppSpace.gutter,
            AppSpace.gutter + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );

/// A yes/no question with consequences. True for yes.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  bool danger = false,
}) async {
  final ok = await _sheet<bool>(
    context,
    Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.headline),
          SizedBox(height: 8.w),
          Text(message,
              style:
                  AppText.body.copyWith(color: context.colors.textSecondary)),
          SizedBox(height: 20.w),
          AppButton(
            label: confirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          SizedBox(height: 8.w),
          AppButton(
            label: cancel,
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Why the booking is being cancelled, and what happens to the money.
Future<String?> showCancelSheet(BuildContext context,
    {required Booking booking, required bool artisan}) {
  final reasons = artisan
      ? [
          "I can't make it at that time",
          'It is too far',
          'The client asked me to cancel',
          'Something else'
        ]
      : [
          'My plans changed',
          'I found someone else',
          'It is taking too long',
          'I booked by mistake',
          'Something else'
        ];
  return _sheet<String>(context,
      _CancelBody(booking: booking, artisan: artisan, reasons: reasons));
}

class _CancelBody extends StatefulWidget {
  const _CancelBody(
      {required this.booking, required this.artisan, required this.reasons});

  final Booking booking;
  final bool artisan;
  final List<String> reasons;

  @override
  State<_CancelBody> createState() => _CancelBodyState();
}

class _CancelBodyState extends State<_CancelBody> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final refund = widget.artisan
        ? 'The client gets a full refund, and the booking leaves your schedule.'
        : widget.booking.payment == PaymentState.held
            ? 'You get your full payment back, usually within a day.'
            : 'You have not paid, so there is nothing to refund.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            widget.booking.status == BookingStatus.requested
                ? 'Cancel this request?'
                : 'Cancel this booking?',
            style: AppText.headline),
        SizedBox(height: 8.w),
        Text(refund, style: AppText.body.copyWith(color: c.textSecondary)),
        SizedBox(height: 16.w),
        Text('Why are you cancelling?',
            style: AppText.labelSmall.copyWith(color: c.textSecondary)),
        SizedBox(height: 8.w),
        Wrap(
          spacing: 8.w,
          runSpacing: 2.w,
          children: [
            for (final r in widget.reasons)
              PromptChip(
                  label: r,
                  selected: _reason == r,
                  onTap: () => setState(() => _reason = r)),
          ],
        ),
        SizedBox(height: 20.w),
        AppButton(
          label: 'Cancel booking',
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(
                    widget.artisan
                        ? 'The artisan cancelled: ${_reason!.toLowerCase()}.'
                        : 'You cancelled: ${_reason!.toLowerCase()}.',
                  ),
        ),
        SizedBox(height: 8.w),
        AppButton(
            label: 'Keep it',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// A new time for the booking.
Future<TimeWindow?> showRescheduleSheet(BuildContext context) async {
  final picked = await _sheet<Object>(context, const _RescheduleBody());
  if (picked is TimeWindow) return picked;
  if (picked == 'pick' && context.mounted) return showDayPicker(context);
  return null;
}

class _RescheduleBody extends StatelessWidget {
  const _RescheduleBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Move to another time', style: AppText.headline),
        SizedBox(height: 8.w),
        Text('We\'ll ask your artisan to confirm the new time.',
            style: AppText.body.copyWith(color: context.colors.textSecondary)),
        SizedBox(height: 16.w),
        Wrap(
          spacing: 8.w,
          children: [
            for (final (label, w) in suggestedWindows(DateTime.now()))
              PromptChip(
                  label: label, onTap: () => Navigator.of(context).pop(w)),
            PromptChip(
                label: 'Pick a day',
                icon: IconsaxPlusLinear.calendar_1,
                onTap: () => Navigator.of(context).pop('pick')),
          ],
        ),
      ],
    );
  }
}

/// The client's 4-digit code, typed by the artisan on arrival.
Future<String?> showStartCodeSheet(BuildContext context,
        {required String clientName}) =>
    _sheet<String>(context, _StartCodeBody(clientName: clientName));

class _StartCodeBody extends StatefulWidget {
  const _StartCodeBody({required this.clientName});

  final String clientName;

  @override
  State<_StartCodeBody> createState() => _StartCodeBodyState();
}

class _StartCodeBodyState extends State<_StartCodeBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Start the job', style: AppText.headline),
        SizedBox(height: 8.w),
        Text(
          'Ask ${widget.clientName} for the 4-digit start code in their booking. It confirms you are at the right place.',
          style: AppText.body.copyWith(color: context.colors.textSecondary),
        ),
        SizedBox(height: 18.w),
        OtpCodeField(
          controller: _controller,
          length: 4,
          autofocus: true,
          onCompleted: (code) {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(code);
          },
        ),
      ],
    );
  }
}

/// Stars and a few words. Returns (stars, words).
Future<(int, String?)?> showReviewSheet(
  BuildContext context, {
  required String name,
  required String service,
  String? photo,
}) =>
    _sheet<(int, String?)>(
        context, _ReviewBody(name: name, service: service, photo: photo));

class _ReviewBody extends StatefulWidget {
  const _ReviewBody({required this.name, required this.service, this.photo});

  final String name;
  final String service;
  final String? photo;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  int _stars = 5;
  final _text = TextEditingController();
  final _tags = <String>{};

  static const _praise = [
    'On time',
    'Did great work',
    'Fair price',
    'Tidy',
    'Polite',
    'Explained everything'
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _word => switch (_stars) {
        5 => 'Excellent',
        4 => 'Good',
        3 => 'Okay',
        2 => 'Not great',
        _ => 'Poor',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = widget.name.split(' ').first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppAvatar(
                name: widget.name, image: imageFor(widget.photo), size: 48.w),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How did $first do?', style: AppText.title),
                  Text(widget.service,
                      style:
                          AppText.bodySmall.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20.w),
        Semantics(
          label: '$_stars out of 5 stars, $_word',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _stars = i);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: Icon(
                      i <= _stars
                          ? IconsaxPlusBold.star_1
                          : IconsaxPlusLinear.star_1,
                      size: 40.w,
                      color: c.rating,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 6.w),
        Center(
            child: Text(_word,
                style: AppText.labelSmall.copyWith(color: c.textSecondary))),
        SizedBox(height: 16.w),
        Wrap(
          spacing: 8.w,
          children: [
            for (final t in _praise)
              PromptChip(
                label: t,
                selected: _tags.contains(t),
                onTap: () => setState(
                    () => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
              ),
          ],
        ),
        SizedBox(height: 12.w),
        AppTextField(
          controller: _text,
          label: 'Anything else? (optional)',
          hint: 'Share your experience with $first',
          textCapitalization: TextCapitalization.sentences,
        ),
        SizedBox(height: 20.w),
        AppButton(
          label: 'Post review',
          onPressed: () {
            final words = [
              ..._tags,
              if (_text.text.trim().isNotEmpty) _text.text.trim()
            ].join('. ');
            Navigator.of(context).pop((_stars, words.isEmpty ? null : words));
          },
        ),
        AppButton(
            label: 'Not now',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
