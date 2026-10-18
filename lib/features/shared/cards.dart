import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/models/models.dart';

/// Artisans, jobs and bookings as cards and rows. Every screen shows them
/// the same way: trust signals (verified, rating, jobs done), then where,
/// then price.

String categoryName(String id) => Trades.byId(id).name;

IconData categoryIcon(String id) => CategoryIcons.of(Trades.byId(id).iconKey);

/// "1.2 km" or "Wuse 2" when the distance is from the city centre.
String whereLabel(Artisan a, {required bool hasArea}) =>
    hasArea ? '${a.distanceKm.toStringAsFixed(1)} km' : a.area;

/// A top-rated artisan as a photo, for the editorial rails: their work in
/// the picture, who they are and what they charge over it.
class ArtisanPhotoCard extends StatelessWidget {
  const ArtisanPhotoCard({
    super.key,
    required this.artisan,
    required this.onTap,
    this.width = 236,
    this.height = 200,
    this.hasArea = true,
    this.saved,
    this.onSave,
    this.tag,
    this.tagIcon,
    this.onBook,
    this.large = false,
  });

  final Artisan artisan;
  final VoidCallback onTap;
  final double width;
  final double height;
  final bool hasArea;

  /// Null hides the heart.
  final bool? saved;
  final VoidCallback? onSave;

  /// Replaces "Free today", for example "Top pick near you".
  final String? tag;
  final IconData? tagIcon;
  final VoidCallback? onBook;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = imageFor(artisan.coverPhoto ?? artisan.photo);
    final w = width.w;
    final h = height.w;
    final radius = BorderRadius.circular(22.w);
    final onPhoto = photo != null;
    final fg = onPhoto ? Colors.white : c.textPrimary;
    final fg2 =
        onPhoto ? Colors.white.withValues(alpha: 0.86) : c.textSecondary;
    return Pressable(
      onTap: onTap,
      focusRadius: radius,
      semanticLabel: '${artisan.name}, ${artisan.trade}, rated '
          '${artisan.rating.toStringAsFixed(1)}, from ${Naira.format(artisan.startingPrice)}',
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              if (onPhoto)
                Positioned.fill(
                  child: Image(
                    image: photo,
                    fit: BoxFit.cover,
                    alignment:
                        Alignment(artisan.coverFocusX, artisan.coverFocusY),
                  ),
                )
              else
                Positioned.fill(child: _NoPhoto(artisan: artisan)),
              if (onPhoto)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.38, 1],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12.w,
                top: 12.w,
                child: _Tag(
                  label: tag ??
                      (artisan.isAvailableToday ? 'Free today' : 'Busy today'),
                  icon: tagIcon,
                  dot: tag == null
                      ? (artisan.isAvailableToday ? c.online : c.warning)
                      : null,
                ),
              ),
              if (saved != null)
                Positioned(
                  right: 4.w,
                  top: 4.w,
                  child: _Heart(
                      saved: saved!, onTap: onSave, name: artisan.firstName),
                ),
              Positioned(
                left: 14.w,
                right: onBook == null ? 14.w : 96.w,
                bottom: 14.w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            artisan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (large ? AppText.title : AppText.titleSmall)
                                .copyWith(
                                    color: fg, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (artisan.isVerified) ...[
                          SizedBox(width: 5.w),
                          Icon(
                            IconsaxPlusBold.verify,
                            size: large ? 18.w : 15.w,
                            color: onPhoto ? Colors.white : c.verified,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2.w),
                    Text(
                      '${artisan.trade} · ${whereLabel(artisan, hasArea: hasArea)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall
                          .copyWith(color: fg2, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 6.w),
                    Row(
                      children: [
                        Icon(IconsaxPlusBold.star_1,
                            size: 14.w, color: c.rating),
                        SizedBox(width: 3.w),
                        Text(
                          artisan.rating.toStringAsFixed(1),
                          style: AppText.caption
                              .copyWith(color: fg, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          ' (${artisan.reviewCount})',
                          style: AppText.caption.copyWith(color: fg2),
                        ),
                        Flexible(
                          child: Text(
                            '  ·  from ${Naira.format(artisan.startingPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: AppText.caption.copyWith(
                                color: fg, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onBook != null)
                Positioned(
                  right: 14.w,
                  bottom: 14.w,
                  child: AppButton(
                    label: 'Book',
                    onPressed: onBook,
                    variant: AppButtonVariant.inverse,
                    size: AppButtonSize.small,
                    expand: false,
                    semanticLabel: 'Book ${artisan.firstName}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// For artisans with no photo yet: their initials on a soft tint, and the
/// trade's icon.
class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.artisan});

  final Artisan artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surfaceMuted,
      child: Stack(
        children: [
          Positioned(
            right: -18.w,
            top: 30.w,
            child: Icon(categoryIcon(artisan.categoryId),
                size: 120.w, color: c.border),
          ),
          Positioned(
            left: 14.w,
            top: 54.w,
            child: AppAvatar(name: artisan.name, size: 52.w),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon, this.dot});

  final String label;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28.w,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 7.w,
              height: 7.w,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            SizedBox(width: 6.w),
          ],
          if (icon != null) ...[
            Icon(icon, size: 14.w, color: const Color(0xFF171717)),
            SizedBox(width: 5.w),
          ],
          Text(
            label,
            style: AppText.caption.copyWith(
              color: const Color(0xFF171717),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.saved, required this.onTap, required this.name});

  final bool saved;
  final VoidCallback? onTap;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? 'Saved $name' : 'Save $name',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48.w,
          height: 48.w,
          child: Center(
            child: Container(
              width: 34.w,
              height: 34.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                shape: BoxShape.circle,
              ),
              child: Icon(
                saved ? IconsaxPlusBold.heart : IconsaxPlusLinear.heart,
                size: 18.w,
                color: saved ? c.brand : const Color(0xFF171717),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An artisan as a list row: face, name, trade, rating and price. One tap
/// target.
class ArtisanRow extends StatelessWidget {
  const ArtisanRow({
    super.key,
    required this.artisan,
    required this.onTap,
    this.hasArea = true,
    this.divider = true,
    this.trailing,
  });

  final Artisan artisan;
  final VoidCallback onTap;
  final bool hasArea;
  final bool divider;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel: '${artisan.name}, ${artisan.trade}, '
          '${artisan.isVerified ? 'verified, ' : ''}rated ${artisan.rating.toStringAsFixed(1)} '
          'from ${artisan.reviewCount} reviews, ${whereLabel(artisan, hasArea: hasArea)}, '
          'from ${Naira.format(artisan.startingPrice)}',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.w),
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: c.border)) : null,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(
                  name: artisan.name,
                  image: imageFor(artisan.photo),
                  size: 56.w,
                  shape: AvatarShape.rounded,
                ),
                if (artisan.isAvailableToday)
                  Positioned(
                    right: -2.w,
                    bottom: -2.w,
                    child: Container(
                      width: 14.w,
                      height: 14.w,
                      decoration: BoxDecoration(
                        color: c.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          artisan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleSmall,
                        ),
                      ),
                      if (artisan.isVerified) ...[
                        SizedBox(width: 4.w),
                        const VerifiedBadge(size: 15),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.w),
                  Text(
                    '${artisan.trade} · ${whereLabel(artisan, hasArea: hasArea)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                  SizedBox(height: 4.w),
                  RatingLabel(
                      rating: artisan.rating, count: artisan.reviewCount),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            trailing ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('from',
                        style: AppText.caption.copyWith(color: c.textTertiary)),
                    Text(Naira.format(artisan.startingPrice),
                        style: AppText.titleSmall),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

/// A small photo card for grids.
class ArtisanTile extends StatelessWidget {
  const ArtisanTile({super.key, required this.artisan, required this.onTap});

  final Artisan artisan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = imageFor(artisan.coverPhoto ?? artisan.photo);
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '${artisan.name}, ${artisan.trade}, rated ${artisan.rating.toStringAsFixed(1)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18.w),
            child: SizedBox(
              height: 120.w,
              width: double.infinity,
              child: photo != null
                  ? Image(
                      image: photo,
                      fit: BoxFit.cover,
                      alignment:
                          Alignment(artisan.coverFocusX, artisan.coverFocusY),
                    )
                  : _NoPhoto(artisan: artisan),
            ),
          ),
          SizedBox(height: 8.w),
          Row(
            children: [
              Flexible(
                child: Text(
                  artisan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleSmall,
                ),
              ),
              if (artisan.isVerified) ...[
                SizedBox(width: 4.w),
                const VerifiedBadge(size: 14),
              ],
            ],
          ),
          SizedBox(height: 2.w),
          Row(
            children: [
              Icon(IconsaxPlusBold.star_1, size: 13.w, color: c.rating),
              SizedBox(width: 3.w),
              Flexible(
                child: Text(
                  '${artisan.rating.toStringAsFixed(1)} · ${artisan.trade}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A square icon tile for a trade.
class TradeIcon extends StatelessWidget {
  const TradeIcon({super.key, required this.categoryId, this.size = 48});

  final String categoryId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(size.w * 0.3),
      ),
      child: Icon(categoryIcon(categoryId),
          size: size.w * 0.46, color: c.textPrimary),
    );
  }
}

/// A photo thumbnail, cropped square.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb(
      {super.key,
      required this.image,
      this.size = 56,
      this.focus = Alignment.center});

  final String image;
  final double size;
  final Alignment focus;

  @override
  Widget build(BuildContext context) {
    final provider = imageFor(image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size.w * 0.26),
      child: SizedBox.square(
        dimension: size.w,
        child: provider == null
            ? ColoredBox(color: context.colors.surfaceMuted)
            : Image(image: provider, fit: BoxFit.cover, alignment: focus),
      ),
    );
  }
}

/// "₦8,000 – ₦12,000", or "Open to quotes" when there is no budget.
String budgetLabel(int? min, int? max) {
  if (min == null && max == null) return 'Open to quotes';
  return Naira.range(min, max);
}

/// A job on the board: a photo of the problem (or the trade's icon), what
/// it is, the budget and where, then how fresh it is and how contested.
/// A job's budget, short enough for a map pin: "₦8k–12k", "₦5k", "Quote".
String pinPrice(JobPost j) {
  final low = j.budgetMin, high = j.budgetMax;
  if (low == null && high == null) return 'Quote';
  if (low == null || high == null || low == high) {
    return '₦${(low ?? high)! ~/ 1000}k';
  }
  return '₦${low ~/ 1000}k–${high ~/ 1000}k';
}

class JobTile extends StatelessWidget {
  const JobTile(
      {super.key,
      required this.job,
      required this.onTap,
      this.divider = true,
      this.hasArea = true});

  final JobPost job;
  final VoidCallback onTap;
  final bool divider;
  final bool hasArea;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final where = hasArea
        ? '${job.area} · ${job.distanceKm.toStringAsFixed(1)} km'
        : job.area;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${job.title}. ${budgetLabel(job.budgetMin, job.budgetMax)}. $where. '
          'Posted ${RelativeTime.spoken(job.postedAt)}. '
          '${job.quoteCount == 0 ? 'No quotes yet' : '${job.quoteCount} quotes'}',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.w),
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: c.border)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            job.photos.isNotEmpty
                ? PhotoThumb(image: job.photos.first, size: 56)
                : TradeIcon(categoryId: job.categoryId, size: 56),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleSmall),
                  SizedBox(height: 3.w),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: budgetLabel(job.budgetMin, job.budgetMax),
                        style: AppText.bodySmall.copyWith(
                            fontWeight: FontWeight.w700, color: c.textPrimary),
                      ),
                      TextSpan(
                          text: '  ·  $where',
                          style: AppText.bodySmall
                              .copyWith(color: c.textSecondary)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6.w),
                  Wrap(
                    spacing: 10.w,
                    runSpacing: 4.w,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (job.isUrgent)
                        const StatusTag(
                            label: 'Urgent',
                            tone: TagTone.warning,
                            icon: IconsaxPlusBold.flash_1),
                      Text(RelativeTime.short(job.postedAt),
                          style:
                              AppText.caption.copyWith(color: c.textTertiary)),
                      if (job.quoteCount == 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6.w,
                              height: 6.w,
                              decoration: BoxDecoration(
                                  color: c.success, shape: BoxShape.circle),
                            ),
                            SizedBox(width: 5.w),
                            Text('Be the first to quote',
                                style: AppText.caption.copyWith(
                                    color: c.success,
                                    fontWeight: FontWeight.w600)),
                          ],
                        )
                      else
                        Text(
                            '${job.quoteCount} quote${job.quoteCount == 1 ? '' : 's'}',
                            style: AppText.caption
                                .copyWith(color: c.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a booking's status reads, for each side.
(String, TagTone) bookingStatus(Booking b, {required bool artisan}) =>
    switch (b.status) {
      BookingStatus.requested => (
          artisan
              ? 'New request'
              : 'Waiting for ${b.counterpartName.split(' ').first}',
          TagTone.warning
        ),
      BookingStatus.confirmed => ('Confirmed', TagTone.success),
      BookingStatus.onTheWay => ('On the way', TagTone.info),
      BookingStatus.inProgress => ('In progress', TagTone.info),
      BookingStatus.completed => b.payment == PaymentState.held
          ? (
              artisan ? 'Waiting for client' : 'Confirm it\'s done',
              TagTone.brand
            )
          : ('Done', TagTone.neutral),
      BookingStatus.cancelled => ('Cancelled', TagTone.neutral),
    };

/// A booking as a list row.
class BookingTile extends StatelessWidget {
  const BookingTile(
      {super.key,
      required this.booking,
      required this.onTap,
      required this.artisan,
      this.divider = true});

  final Booking booking;
  final VoidCallback onTap;

  /// Seen by the artisan.
  final bool artisan;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, tone) = bookingStatus(booking, artisan: artisan);
    final when = Schedule.dayAndTime(booking.scheduledAt);
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${booking.serviceName} with ${booking.counterpartName}, $when, $label',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.w),
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: c.border)) : null,
        ),
        child: Row(
          children: [
            AppAvatar(
              name: booking.counterpartName,
              image: imageFor(booking.counterpartPhoto),
              size: 52.w,
              shape: AvatarShape.rounded,
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleSmall),
                  SizedBox(height: 2.w),
                  // First name: the photo says who, and the time must fit.
                  Text(
                    '${booking.counterpartName.split(' ').first} · $when',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                  SizedBox(height: 6.w),
                  Row(
                    children: [
                      StatusTag(label: label, tone: tone),
                      if (booking.yourRating != null) ...[
                        SizedBox(width: 8.w),
                        Icon(IconsaxPlusBold.star_1,
                            size: 13.w, color: c.rating),
                        SizedBox(width: 3.w),
                        Text('${booking.yourRating}',
                            style: AppText.caption
                                .copyWith(color: c.textSecondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (booking.price != null) ...[
              // A gap, so a long name and time end in "…" before the price.
              SizedBox(width: 12.w),
              Text(Naira.format(artisan ? booking.price! : booking.total),
                  style: AppText.titleSmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// A heading for a section of a screen, with an optional action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title,
      {super.key, this.action, this.onAction, this.count});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppText.title),
        ),
        if (count != null && count! > 0) ...[
          SizedBox(width: 8.w),
          CountBadge(count!),
        ],
        const Spacer(),
        if (action != null)
          Semantics(
            button: true,
            excludeSemantics: true,
            label: '$action, $title',
            child: GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: AppSize.minTapTarget),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.only(left: 12.w),
                    child: Text(action!,
                        style: AppText.labelSmall.copyWith(color: c.brandText)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
