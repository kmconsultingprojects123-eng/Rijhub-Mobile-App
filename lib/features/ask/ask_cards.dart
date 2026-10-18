import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../shared/cards.dart';
import 'ask_flow.dart';

/// Who can help: a map of who is free nearby, the best match, two more.
class MatchesCard extends StatelessWidget {
  const MatchesCard({
    super.key,
    required this.matches,
    required this.onBook,
    required this.onOpen,
    required this.onSeeAll,
  });

  final BotMatches matches;
  final ValueChanged<Artisan> onBook;
  final ValueChanged<Artisan> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final best = matches.best;
    final others =
        matches.artisans.where((a) => a.id != best.id).take(2).toList();
    final centre = AbujaPlaces.centreOf(matches.area);
    final hasArea = matches.area != null;
    final plural =
        Trades.byId(matches.triage.categoryId).artisanPlural ?? 'Artisans';
    final photo = imageFor(best.coverPhoto ?? best.photo);
    return CardMessage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 170.w,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RijMap(
                    lat: centre.lat,
                    lng: centre.lng,
                    kmAcross: hasArea ? 5 : 10,
                    fit: true,
                    showMe: hasArea,
                    semanticLabel:
                        'Map of ${matches.free} ${TextCase.midSentence(plural)} free near you',
                    markers: [
                      for (final a in matches.artisans)
                        if (a.location != null)
                          MapMarker(
                            lat: a.location!.lat,
                            lng: a.location!.lng,
                            child: FacePin(
                              name: a.name,
                              photo: a.photo,
                              size: a.id == best.id ? 36 : 30,
                              selected: a.id == best.id,
                              free: a.isAvailableToday,
                            ),
                          ),
                    ],
                  ),
                ),
                Positioned(
                  left: 10.w,
                  top: 10.w,
                  child: MapPill(
                    label:
                        '${matches.free} free ${hasArea ? 'near ${matches.area}' : 'in Abuja'}',
                    dotColor: c.online,
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () => onOpen(best),
            pressedScale: 0.99,
            focusOffset: 0,
            semanticLabel:
                'Best match: ${best.name}, rated ${best.rating.toStringAsFixed(1)}, '
                'from ${Naira.format(best.startingPrice)}. Open profile',
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14.w),
                    child: SizedBox(
                      width: 84.w,
                      height: 92.w,
                      child: photo != null
                          ? Image(
                              image: photo,
                              fit: BoxFit.cover,
                              alignment:
                                  Alignment(best.coverFocusX, best.coverFocusY),
                            )
                          : Center(
                              child: AppAvatar(name: best.name, size: 56.w)),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(IconsaxPlusBold.medal_star,
                                size: 14.w, color: c.brandText),
                            SizedBox(width: 4.w),
                            Text('Best match',
                                style: AppText.caption.copyWith(
                                    color: c.brandText,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        SizedBox(height: 3.w),
                        Row(
                          children: [
                            Flexible(
                              child: Text(best.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.titleSmall
                                      .copyWith(fontWeight: FontWeight.w700)),
                            ),
                            if (best.isVerified) ...[
                              SizedBox(width: 4.w),
                              const VerifiedBadge(size: 15),
                            ],
                          ],
                        ),
                        SizedBox(height: 3.w),
                        RatingLabel(
                            rating: best.rating, count: best.reviewCount),
                        SizedBox(height: 6.w),
                        Text(
                          'from ${Naira.format(best.startingPrice)} · ${whereLabel(best, hasArea: hasArea)}',
                          style: AppText.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  AppButton(
                    label: 'Book',
                    size: AppButtonSize.small,
                    expand: false,
                    semanticLabel: 'Book ${best.firstName}',
                    onPressed: () => onBook(best),
                  ),
                ],
              ),
            ),
          ),
          for (final a in others) ...[
            Divider(
                height: 1,
                thickness: 1,
                color: c.border,
                indent: 12.w,
                endIndent: 12.w),
            Pressable(
              onTap: () => onOpen(a),
              pressedScale: 0.99,
              focusOffset: 0,
              semanticLabel:
                  '${a.name}, rated ${a.rating.toStringAsFixed(1)}, from ${Naira.format(a.startingPrice)}',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
                child: Row(
                  children: [
                    AppAvatar(
                        name: a.name, image: imageFor(a.photo), size: 36.w),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.labelSmall),
                          SizedBox(height: 2.w),
                          RatingLabel(rating: a.rating, count: a.reviewCount),
                        ],
                      ),
                    ),
                    Text('from ${Naira.format(a.startingPrice)}',
                        style: AppText.labelSmall),
                    SizedBox(width: 4.w),
                    Icon(IconsaxPlusLinear.arrow_right_3,
                        size: 16.w, color: c.textTertiary),
                  ],
                ),
              ),
            ),
          ],
          Divider(height: 1, thickness: 1, color: c.border),
          Semantics(
            button: true,
            child: InkWell(
              onTap: onSeeAll,
              child: SizedBox(
                height: 48.w,
                child: Center(
                  child: Text(
                    'See all ${matches.artisans.length} ${TextCase.midSentence(plural)}',
                    style: AppText.labelSmall.copyWith(color: c.brandText),
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

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.w, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(child: Text(text, style: AppText.body)),
        ],
      ),
    );
  }
}

/// The booking, ready to confirm: who, what, when, where, and the price.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.active,
    required this.busy,
    required this.onConfirm,
    required this.onChange,
    this.onAddService,
  });

  final BotSummary summary;

  /// Adds another of the artisan's services; null hides the link.
  final VoidCallback? onAddService;

  /// The latest summary, not yet confirmed: it keeps its buttons.
  final bool active;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = summary.draft;
    final p = summary.price;
    return CardMessage(
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(
                  name: d.artisan.name,
                  image: imageFor(d.artisan.photo),
                  size: 46.w,
                  shape: AvatarShape.rounded),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.service.name,
                        style: AppText.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: 2.w),
                    Text('with ${d.artisan.name}',
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.w),
          _Line(IconsaxPlusLinear.calendar_1, windowLabel(d.window)),
          _Line(IconsaxPlusLinear.location,
              [d.landmark, d.area].whereType<String>().join(', ')),
          Divider(height: 20.w, thickness: 1, color: c.border),
          if (summary.services.isEmpty)
            InfoLine(label: d.service.name, value: Naira.format(p.price))
          else
            for (final s in summary.services)
              InfoLine(label: s.name, value: Naira.format(s.price)),
          if (active && onAddService != null)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Add a service',
                leading: const Icon(IconsaxPlusLinear.add),
                variant: AppButtonVariant.tertiary,
                size: AppButtonSize.small,
                expand: false,
                onPressed: busy ? null : onAddService,
              ),
            ),
          InfoLine(label: 'Service fee', value: Naira.format(p.fee)),
          InfoLine(label: 'Total', value: Naira.format(p.total), strong: true),
          SizedBox(height: 8.w),
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
                color: c.successSubtle,
                borderRadius: BorderRadius.circular(12.w)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(IconsaxPlusBold.shield_tick, size: 18.w, color: c.success),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'Paid safely: ${d.artisan.firstName} only gets it when you say the job is done.',
                    style: AppText.bodySmall.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          if (active) ...[
            SizedBox(height: 12.w),
            Row(
              children: [
                AppButton(
                  label: 'Change',
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  onPressed: busy ? null : onChange,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: AppButton(
                    label: 'Confirm · ${Naira.format(p.total)}',
                    isLoading: busy,
                    onPressed: busy ? null : onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The request sent: its status, and the start code for later.
class BookedCard extends StatelessWidget {
  const BookedCard({super.key, required this.booking, required this.onOpen});

  final Booking booking;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, tone) = bookingStatus(booking, artisan: false);
    return Pressable(
      onTap: onOpen,
      pressedScale: 0.99,
      semanticLabel:
          '${booking.serviceName} with ${booking.counterpartName}, ${Schedule.dayAndTime(booking.scheduledAt)}, $label. Open booking',
      child: CardMessage(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusTag(
                    label: label, tone: tone, icon: IconsaxPlusLinear.clock),
                const Spacer(),
                Text(Naira.format(booking.total), style: AppText.labelSmall),
                SizedBox(width: 4.w),
                Icon(IconsaxPlusLinear.arrow_right_3,
                    size: 16.w, color: c.textTertiary),
              ],
            ),
            SizedBox(height: 10.w),
            Text('${booking.serviceName} with ${booking.counterpartName}',
                style:
                    AppText.titleSmall.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: 2.w),
            Text(Schedule.dayAndTime(booking.scheduledAt),
                style: AppText.bodySmall.copyWith(color: c.textSecondary)),
            if (booking.startCode != null) ...[
              SizedBox(height: 10.w),
              Row(
                children: [
                  Icon(IconsaxPlusLinear.key,
                      size: 18.w, color: c.textSecondary),
                  SizedBox(width: 8.w),
                  Text('Start code ',
                      style: AppText.body.copyWith(color: c.textSecondary)),
                  Text(booking.startCode!,
                      style: AppText.title.copyWith(letterSpacing: 2)),
                ],
              ),
              Text(
                'Give it to ${booking.counterpartName.split(' ').first} when they arrive.',
                style: AppText.caption.copyWith(color: c.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The job, sent out for quotes.
class JobPostedCard extends StatelessWidget {
  const JobPostedCard({super.key, required this.posted, required this.onOpen});

  final BotJobPosted posted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = posted.job;
    final plural = Trades.byId(job.categoryId).artisanPlural ?? 'artisans';
    return Pressable(
      onTap: onOpen,
      pressedScale: 0.99,
      semanticLabel:
          '${job.title}. ${posted.to != null ? 'Open the request' : 'See quotes'}',
      child: CardMessage(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TradeIcon(categoryId: job.categoryId, size: 44),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.title,
                          style: AppText.titleSmall
                              .copyWith(fontWeight: FontWeight.w700)),
                      SizedBox(height: 2.w),
                      Text(
                        posted.to != null
                            ? 'Sent to ${posted.to!.name}'
                            : 'Sent to ${posted.sentTo} ${TextCase.midSentence(plural)} near ${job.area}',
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (job.budgetMin != null) ...[
              SizedBox(height: 10.w),
              InfoLine(
                  label: 'Usual price',
                  value: Naira.range(job.budgetMin, job.budgetMax)),
            ],
          ],
        ),
      ),
    );
  }
}

/// An artisan's services as a short menu: tap one to book it, or ask for a
/// price for something else.
class ServicesCard extends StatelessWidget {
  const ServicesCard(
      {super.key,
      required this.item,
      required this.onPick,
      required this.onOther,
      this.active = true});

  final BotServices item;
  final ValueChanged<ServiceOffer> onPick;
  final VoidCallback onOther;

  /// False once a choice is made; the menu stays as a record.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(
            {required String title,
            String? detail,
            String? price,
            required VoidCallback onTap,
            bool last = false}) =>
        Semantics(
          button: true,
          enabled: active,
          label: [title, if (price != null) price].join(', '),
          excludeSemantics: true,
          child: InkWell(
            onTap: active ? onTap : null,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.w),
              decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(bottom: BorderSide(color: c.border))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.labelSmall),
                        if (detail != null)
                          Text(detail,
                              style: AppText.caption
                                  .copyWith(color: c.textTertiary)),
                      ],
                    ),
                  ),
                  if (price != null) ...[
                    SizedBox(width: 8.w),
                    Text(price, style: AppText.labelSmall),
                  ],
                  if (active) ...[
                    SizedBox(width: 6.w),
                    Icon(IconsaxPlusLinear.arrow_right_3,
                        size: 16.w, color: c.textTertiary),
                  ],
                ],
              ),
            ),
          ),
        );
    return CardMessage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in item.services)
            row(
              title: s.name,
              detail: s.unit,
              price: s.priceMax == null
                  ? Naira.format(s.price)
                  : Naira.range(s.price, s.priceMax),
              onTap: () => onPick(s),
            ),
          row(
            title: 'Something else',
            detail: 'Describe it, and ${item.artisan.firstName} sends a price',
            onTap: onOther,
            last: true,
          ),
        ],
      ),
    );
  }
}

/// The welcome's opening card: a real artisan at work, and how many
/// ID-checked artisans RijHub has.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key, required this.stats});

  final MarketStats stats;

  @override
  Widget build(BuildContext context) {
    final photo = imageFor(stats.cover);
    final count = stats.verifiedArtisans
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return Padding(
      padding: EdgeInsets.only(bottom: 10.w),
      child: Semantics(
        container: true,
        label:
            '$count ID-checked artisans across Abuja, rated ${stats.averageRating} on average',
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.w),
            child: AspectRatio(
              aspectRatio: 1.35,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null) Image(image: photo, fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 1],
                        colors: [Colors.transparent, Color(0xD9000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14.w,
                    right: 14.w,
                    bottom: 14.w,
                    child: Row(
                      children: [
                        if (stats.faces.isNotEmpty) ...[
                          FaceStack(
                              people: [for (final f in stats.faces) ('', f)],
                              size: 26),
                          SizedBox(width: 10.w),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$count ID-checked artisans',
                                  style: AppText.titleSmall.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                'across Abuja · ${stats.averageRating.toStringAsFixed(1)} average rating',
                                style: AppText.caption.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trades as chips in the conversation, up to three picked. The common
/// ones show first; "More trades" opens the rest.
class TradePicker extends StatefulWidget {
  const TradePicker(
      {super.key,
      required this.picked,
      required this.onToggle,
      this.locked = false});

  final Set<String> picked;
  final ValueChanged<String> onToggle;

  /// Sent: the picks stay as a record and can't change.
  final bool locked;

  @override
  State<TradePicker> createState() => _TradePickerState();
}

class _TradePickerState extends State<TradePicker> {
  static const _common = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown = widget.locked
        ? Trades.all.where((t) => widget.picked.contains(t.id))
        : (_all ? Trades.all : Trades.all.take(_common));
    return Padding(
      padding: EdgeInsets.only(bottom: 8.w),
      child: Wrap(
        spacing: 8.w,
        children: [
          for (final t in shown)
            PromptChip(
              label: t.name,
              icon: CategoryIcons.of(t.iconKey),
              selected: widget.picked.contains(t.id),
              onTap: widget.locked ? null : () => widget.onToggle(t.id),
            ),
          if (!widget.locked && !_all)
            PromptChip(
              label: 'More trades',
              icon: IconsaxPlusLinear.add,
              onTap: () => setState(() => _all = true),
            ),
        ],
      ),
    );
  }
}

/// This week's jobs for an artisan's trades: price pins on a map, then the
/// newest job.
class JobsTeaserCard extends StatelessWidget {
  const JobsTeaserCard({super.key, required this.teaser, required this.onOpen});

  final BotJobsTeaser teaser;
  final ValueChanged<JobPost> onOpen;

  @override
  Widget build(BuildContext context) {
    final centre = AbujaPlaces.centreOf(teaser.area);
    final newest = teaser.jobs.first;
    final hasArea = teaser.area != null;
    return CardMessage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 170.w,
            child: RijMap(
              lat: centre.lat,
              lng: centre.lng,
              kmAcross: hasArea ? 6 : 12,
              fit: !hasArea,
              showMe: hasArea,
              semanticLabel: 'Map of ${teaser.jobs.length} jobs',
              markers: [
                // A few priced jobs read at a glance; the board has the rest.
                for (final j in teaser.jobs
                    .where((j) => j.location != null && j.budgetMin != null)
                    .take(4))
                  MapMarker(
                    lat: j.location!.lat,
                    lng: j.location!.lng,
                    child: PricePin(pinPrice(j), urgent: j.isUrgent),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: JobTile(
                job: newest,
                hasArea: hasArea,
                divider: false,
                onTap: () => onOpen(newest)),
          ),
        ],
      ),
    );
  }
}
