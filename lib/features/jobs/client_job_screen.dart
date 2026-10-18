import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_flow.dart';
import '../booking/booking_sheets.dart';
import '../booking/checkout.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// A client's posted job: what they asked for, and the quotes side by side.
class ClientJobScreen extends StatelessWidget {
  const ClientJobScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Loader<ClientJob>(
      load: () => context.read<ClientJobRepository>().byId(jobId),
      loading: const Scaffold(body: ListSkeleton()),
      builder: (context, job, reload) => _JobView(job: job, reload: reload),
    );
  }
}

enum _Order { price, rating, soonest }

class _JobView extends StatefulWidget {
  const _JobView({required this.job, required this.reload});

  final ClientJob job;
  final Future<void> Function() reload;

  @override
  State<_JobView> createState() => _JobViewState();
}

class _JobViewState extends State<_JobView> {
  _Order _order = _Order.price;

  ClientJob get _job => widget.job;

  List<Quote> get _quotes {
    final list = [..._job.quotes];
    switch (_order) {
      case _Order.price:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _Order.rating:
        list.sort((a, b) => b.artisan.rating.compareTo(a.artisan.rating));
      case _Order.soonest:
        list.sort((a, b) => (a.canStartAt ?? DateTime(3000))
            .compareTo(b.canStartAt ?? DateTime(3000)));
    }
    return list;
  }

  Future<void> _accept(Quote q) async {
    final choice = await showAcceptSheet(context, quote: q);
    if (choice == null || !mounted) return;
    final (price, window) = choice;
    final repo = context.read<ClientJobRepository>();
    final paid = await showCheckout(context,
        total: price + feeOf(price),
        description: '${_job.title} with ${q.artisan.firstName}');
    if (!paid || !mounted) return;
    final booking = await runAction(context,
        () => repo.accept(_job.id, q.id, window: window, price: price));
    if (booking == null || !mounted) return;
    showToast(context, 'Booked ${q.artisan.firstName}. Payment held safely.');
    context.pushReplacement(Routes.booking(booking.id));
  }

  Future<void> _decline(Quote q) async {
    await runAction(context,
        () => context.read<ClientJobRepository>().decline(_job.id, q.id));
    await widget.reload();
  }

  Future<void> _message(Quote q) async {
    final convo =
        await context.read<ChatRepository>().withArtisan(q.artisan.id);
    if (mounted) context.push(Routes.chat(convo.id));
  }

  Future<void> _close() async {
    final ok = await confirmSheet(
      context,
      title: 'Close this job?',
      message: 'Artisans can no longer quote on it. Quotes you have stay here.',
      confirm: 'Close job',
    );
    if (!ok || !mounted) return;
    await runAction(
        context, () => context.read<ClientJobRepository>().close(_job.id));
    await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = _job;
    final g = AppSpace.gutter;
    final open = job.status == JobStatus.open;
    return PageScaffold(
      title: job.title,
      subtitle: '${job.area} · posted ${RelativeTime.short(job.postedAt)}',
      actions: [
        if (open)
          AppIconButton(
            icon: IconsaxPlusLinear.edit_2,
            semanticLabel: 'Edit job',
            onPressed: () async {
              final changed =
                  await context.push<bool>(Routes.editJob(job.id), extra: job);
              if (changed == true) await widget.reload();
            },
          ),
      ],
      body: RefreshIndicator(
        color: c.brandStroke,
        onRefresh: widget.reload,
        child: ListView(
          padding: EdgeInsets.fromLTRB(g, 4.w, g, 28.w),
          children: [
            _Banner(job: job),
            SizedBox(height: 20.w),
            if (job.description != null)
              Text(job.description!, style: AppText.body),
            if (job.photos.isNotEmpty) ...[
              SizedBox(height: 12.w),
              Wrap(spacing: 8.w, children: [
                for (final p in job.photos) PhotoThumb(image: p, size: 72)
              ]),
            ],
            SizedBox(height: 12.w),
            InfoLine(
              icon: IconsaxPlusLinear.location,
              label: 'Where',
              value: [job.landmark, job.area].whereType<String>().join(', '),
            ),
            if (job.budgetMin != null || job.budgetMax != null)
              InfoLine(
                  icon: IconsaxPlusLinear.money_2,
                  label: 'Usual price',
                  value: Naira.range(job.budgetMin, job.budgetMax)),
            if (job.quotes.isNotEmpty) ...[
              SizedBox(height: 24.w),
              SectionTitle('Quotes', count: job.pendingQuotes),
              SizedBox(height: 6.w),
              Wrap(
                spacing: 8.w,
                children: [
                  for (final (o, label) in const [
                    (_Order.price, 'Lowest price'),
                    (_Order.rating, 'Top rated'),
                    (_Order.soonest, 'Soonest')
                  ])
                    PromptChip(
                        label: label,
                        solid: _order == o,
                        onTap: () => setState(() => _order = o)),
                ],
              ),
              SizedBox(height: 6.w),
              for (final q in _quotes)
                QuoteCard(
                  quote: q,
                  canAct: open && q.status == QuoteStatus.pending,
                  onAccept: () => _accept(q),
                  onDecline: () => _decline(q),
                  onMessage: () => _message(q),
                  onProfile: () => context.push(Routes.artisan(q.artisan.id)),
                ),
            ],
            if (open) ...[
              SizedBox(height: 16.w),
              Center(
                child: AppButton(
                  label: 'Close this job',
                  variant: AppButtonVariant.tertiary,
                  expand: false,
                  onPressed: _close,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// RijHub's fee on [price], as the booking shows it.
int feeOf(int price) => ((price * 0.05).clamp(300, 2500) / 50).round() * 50;

class _Banner extends StatelessWidget {
  const _Banner({required this.job});

  final ClientJob job;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = job.pendingQuotes;
    final (icon, title, sub, bg, fg) = switch (job.status) {
      JobStatus.booked => (
          IconsaxPlusBold.tick_circle,
          'Booked',
          'You accepted a quote. Follow it in Bookings.',
          c.successSubtle,
          c.success
        ),
      JobStatus.closed => (
          IconsaxPlusLinear.lock_1,
          'Closed',
          'This job no longer takes quotes.',
          c.surfaceMuted,
          c.textSecondary
        ),
      JobStatus.open when n == 0 && job.quotes.isEmpty => (
          IconsaxPlusLinear.clock,
          'Waiting for quotes',
          'Artisans near you are looking at it. Most quotes come within 30 minutes.',
          c.warningSubtle,
          c.warning
        ),
      JobStatus.open => (
          IconsaxPlusLinear.receipt_2,
          '$n quote${n == 1 ? '' : 's'} to compare',
          'Pick on price, reviews and when they can come. You pay only when you accept.',
          c.brandSubtle,
          c.brandText
        ),
    };
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18.w)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22.w, color: fg),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: 2.w),
                Text(sub,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One artisan's quote: who, the price, what they said, and when they can
/// come.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    required this.canAct,
    required this.onAccept,
    required this.onDecline,
    required this.onMessage,
    required this.onProfile,
  });

  final Quote quote;
  final bool canAct;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onMessage;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = quote;
    final a = q.artisan;
    final price = q.priceMax == null
        ? Naira.format(q.price)
        : Naira.range(q.price, q.priceMax);
    return Container(
      margin: EdgeInsets.only(top: 10.w),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.w),
        border: Border.all(color: c.border),
        color: q.status == QuoteStatus.declined ? c.surfaceMuted : c.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: onProfile,
            semanticLabel:
                '${a.name}, rated ${a.rating.toStringAsFixed(1)}. Open profile',
            child: Row(
              children: [
                AppAvatar(name: a.name, image: imageFor(a.photo), size: 44.w),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                              child: Text(a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.titleSmall
                                      .copyWith(fontWeight: FontWeight.w700))),
                          if (a.isVerified) ...[
                            SizedBox(width: 4.w),
                            const VerifiedBadge(size: 14)
                          ],
                        ],
                      ),
                      SizedBox(height: 2.w),
                      RatingLabel(rating: a.rating, count: a.reviewCount),
                    ],
                  ),
                ),
                Icon(IconsaxPlusLinear.arrow_right_3,
                    size: 16.w, color: c.textTertiary),
              ],
            ),
          ),
          SizedBox(height: 12.w),
          // The note drops under a long range rather than squeezing it.
          Wrap(
            spacing: 8.w,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(price,
                  style:
                      AppText.headline.copyWith(fontWeight: FontWeight.w800)),
              Padding(
                padding: EdgeInsets.only(bottom: 4.w),
                child: Text(
                  q.priceMax == null
                      ? 'fixed price'
                      : 'depends on what they find',
                  style: AppText.caption.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
          if (q.message != null) ...[
            SizedBox(height: 10.w),
            Text(q.message!, style: AppText.body),
          ],
          SizedBox(height: 10.w),
          Row(
            children: [
              Icon(IconsaxPlusLinear.calendar_1,
                  size: 16.w, color: c.textSecondary),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  q.canStartAt == null
                      ? 'Flexible on time'
                      : 'Can come ${Schedule.dayAndTime(q.canStartAt!)}',
                  style: AppText.bodySmall.copyWith(color: c.textSecondary),
                ),
              ),
              Text('${a.jobsCompleted} jobs',
                  style: AppText.caption.copyWith(color: c.textTertiary)),
            ],
          ),
          if (q.status != QuoteStatus.pending) ...[
            SizedBox(height: 10.w),
            StatusTag(
              label: switch (q.status) {
                QuoteStatus.accepted => 'Accepted',
                QuoteStatus.declined => 'Declined',
                QuoteStatus.withdrawn => 'Withdrawn',
                QuoteStatus.pending => '',
              },
              tone: q.status == QuoteStatus.accepted
                  ? TagTone.success
                  : TagTone.neutral,
            ),
          ] else if (canAct) ...[
            SizedBox(height: 12.w),
            Row(
              children: [
                AppIconButton(
                    icon: IconsaxPlusLinear.message,
                    filled: true,
                    semanticLabel: 'Message ${a.firstName}',
                    onPressed: onMessage),
                SizedBox(width: 4.w),
                SizedBox(width: 4.w),
                AppButton(
                    label: 'Decline',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: onDecline),
                const Spacer(),
                AppButton(
                  label: 'Accept',
                  size: AppButtonSize.small,
                  expand: false,
                  semanticLabel: 'Accept ${a.firstName}\'s quote of $price',
                  onPressed: onAccept,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Picks the price (for a range) and the time. Returns (price, window).
Future<(int, TimeWindow)?> showAcceptSheet(BuildContext context,
    {required Quote quote}) {
  return showModalBottomSheet<(int, TimeWindow)>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => _AcceptBody(quote: quote),
  );
}

class _AcceptBody extends StatefulWidget {
  const _AcceptBody({required this.quote});

  final Quote quote;

  @override
  State<_AcceptBody> createState() => _AcceptBodyState();
}

class _AcceptBodyState extends State<_AcceptBody> {
  late final List<int> _prices = _options(widget.quote);
  late int _price = _prices.last;
  TimeWindow? _window;
  String? _label;

  /// For a range, five evenly spaced prices from low to high.
  static List<int> _options(Quote q) {
    if (q.priceMax == null) return [q.price];
    final step = (q.priceMax! - q.price) / 4;
    return {
      for (var i = 0; i < 5; i++) ((q.price + step * i) / 500).round() * 500
    }.toList();
  }

  @override
  void initState() {
    super.initState();
    final start = widget.quote.canStartAt;
    if (start != null) {
      _window =
          TimeWindow(start: start, end: start.add(const Duration(hours: 2)));
      _label = windowLabel(_window!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = widget.quote;
    final windows = [
      if (_window != null &&
          !suggestedWindows(DateTime.now())
              .any((w) => w.$2.start == _window!.start))
        (_label!, _window!),
      ...suggestedWindows(DateTime.now()),
    ];
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Book ${q.artisan.firstName}', style: AppText.headline),
            SizedBox(height: 6.w),
            Text(
                'You pay now; ${q.artisan.firstName} gets it when you say the job is done.',
                style: AppText.body.copyWith(color: c.textSecondary)),
            if (_prices.length > 1) ...[
              SizedBox(height: 18.w),
              Text('${q.artisan.firstName} quoted a range. Pick a price',
                  style: AppText.labelSmall),
              SizedBox(height: 6.w),
              Wrap(
                spacing: 8.w,
                children: [
                  for (final p in _prices)
                    PromptChip(
                        label: Naira.format(p),
                        selected: _price == p,
                        onTap: () => setState(() => _price = p)),
                ],
              ),
            ],
            SizedBox(height: 18.w),
            Text('When should they come?', style: AppText.labelSmall),
            SizedBox(height: 6.w),
            Wrap(
              spacing: 8.w,
              children: [
                for (final (label, w) in windows)
                  PromptChip(
                    label: label,
                    selected: _window?.start == w.start,
                    onTap: () => setState(() {
                      _window = w;
                      _label = label;
                    }),
                  ),
                PromptChip(
                  label: 'Pick a day',
                  icon: IconsaxPlusLinear.calendar_1,
                  onTap: () async {
                    final w = await showDayPicker(context);
                    if (w != null) {
                      setState(() {
                        _window = w;
                        _label = windowLabel(w);
                      });
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 18.w),
            InfoLine(label: 'Price', value: Naira.format(_price)),
            InfoLine(label: 'Service fee', value: Naira.format(feeOf(_price))),
            InfoLine(
                label: 'Total',
                value: Naira.format(_price + feeOf(_price)),
                strong: true),
            SizedBox(height: 14.w),
            AppButton(
              label: _window == null
                  ? 'Pick a time'
                  : 'Pay ${Naira.format(_price + feeOf(_price))}',
              onPressed: _window == null
                  ? null
                  : () => Navigator.of(context).pop((_price, _window!)),
            ),
          ],
        ),
      ),
    );
  }
}
