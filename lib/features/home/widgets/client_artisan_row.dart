import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/images.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'client_meta_line.dart';

/// A three-line list item: rows are at least this tall, and grow with
/// large text.
double get _minHeight => 88.w;
double get _photoSize => 56.w;

/// Above the first line and below the last: 14 + 60 of text + 14 = 88.
double get _padY => 14.w;

/// Where the text column starts. The hairline between rows starts here
/// too, so it underlines the words, not the photos.
double get _textStart => AppSpace.gutter + _photoSize + AppSpace.s16;

/// "Book again" pads its touch area this far past its words.
double get _linkPad => AppSpace.s8;

final _count = NumberFormat('#,##0', 'en_US');

/// "1 job", "214 jobs".
String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

/// One artisan on the client Home: photo, name and price; trade, rating
/// and jobs done; then when they're free, where they are and how fast they
/// reply. The whole row is one tap target that opens the artisan.
///
/// For an artisan the client has hired before, the price makes way for
/// "Book again" and the last line says when they worked together.
class ClientArtisanRow extends StatelessWidget {
  const ClientArtisanRow({
    super.key,
    required this.artisan,
    required this.showDistance,
    required this.onTap,
    this.hired,
    this.onBookAgain,
    this.divider = true,
  });

  final Artisan artisan;

  /// The client has picked an area, so distances mean something. Without
  /// one, the row names the artisan's neighbourhood instead.
  final bool showDistance;
  final VoidCallback onTap;

  /// Set when the client has hired this artisan before.
  final HiredArtisan? hired;
  final VoidCallback? onBookAgain;

  /// A hairline under the row, from the text column to the screen's edge.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final hired = this.hired;
    final meta = AppText.bodySmall.copyWith(color: c.textSecondary);

    final row = Pressable(
      onTap: onTap,
      semanticLabel: _sentence(now),
      // Rows run edge to edge in a list that clips, so the ring stays in.
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _minHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            _padY,
            AppSpace.gutter,
            _padY,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Centred on the three lines at the default text size; at
              // larger sizes it stays beside the name.
              Padding(
                padding: EdgeInsets.only(top: AppSpace.s2),
                child: _Photo(artisan: artisan),
              ),
              SizedBox(width: AppSpace.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NameLine(
                      artisan: artisan,
                      trailing: hired == null
                          ? _Price(amount: artisan.startingPrice)
                          // Holds the place of the link drawn over it.
                          : const Visibility(
                              visible: false,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: _BookAgainLabel(),
                            ),
                    ),
                    SizedBox(height: AppSpace.s2),
                    ClientMetaLine(style: meta, parts: _record(c)),
                    SizedBox(height: AppSpace.s2),
                    ClientMetaLine(
                      style: meta,
                      parts: hired == null
                          ? _availability(c, now)
                          : _history(c, hired),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final onBookAgain = this.onBookAgain;
    return Stack(
      children: [
        row,
        if (divider)
          PositionedDirectional(
            start: _textStart,
            end: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(height: 1, color: c.border),
            ),
          ),
        // Its own tap target and its own stop for screen readers, so it
        // sits over the row rather than inside it.
        if (hired != null && onBookAgain != null)
          PositionedDirectional(
            top: _linkTop(MediaQuery.textScalerOf(context)),
            end: AppSpace.gutter - _linkPad,
            child: _BookAgainLink(name: artisan.name, onTap: onBookAgain),
          ),
      ],
    );
  }

  /// Puts the link's 48pt touch area on the middle of the name's line.
  static double _linkTop(TextScaler scaler) {
    final style = AppText.titleSmall;
    final line = scaler.scale(style.fontSize!) * style.height!;
    return _padY + line / 2 - AppSize.minTapTarget / 2;
  }

  /// "AC technician · ★ 4.9 (128) · 214 jobs". Someone with no reviews
  /// yet is "New" rather than "★ 0.0 (0)".
  List<InlineSpan> _record(AppColors c) {
    final jobs = artisan.jobsCompleted;
    return [
      TextSpan(text: artisan.trade),
      if (artisan.reviewCount == 0)
        const TextSpan(text: 'New')
      else
        TextSpan(
          children: [
            TextSpan(text: '★\u00A0', style: TextStyle(color: c.rating)),
            TextSpan(
              text: artisan.rating.toStringAsFixed(1),
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: '\u00A0(${_count.format(artisan.reviewCount)})'),
          ],
        ),
      if (jobs > 0)
        TextSpan(text: '${_count.format(jobs)}\u00A0${_plural(jobs, 'job')}'),
    ];
  }

  /// "● Free now · 1.2 km · replies ~10 min"
  List<InlineSpan> _availability(AppColors c, DateTime now) {
    final nextFree = artisan.nextFreeAt;
    final reply = artisan.replyMinutes;
    return [
      if (artisan.isAvailableToday)
        TextSpan(
          text: '●\u00A0Free\u00A0now',
          style: TextStyle(color: c.success),
        )
      else if (nextFree != null)
        TextSpan(text: _FreeAt.short(nextFree, now)),
      TextSpan(text: showDistance ? _km : artisan.area),
      if (reply != null) TextSpan(text: 'replies\u00A0~$reply\u00A0min'),
    ];
  }

  /// "You hired Emeka · 2 Oct · you rated 5★"
  List<InlineSpan> _history(AppColors c, HiredArtisan hired) {
    final rating = hired.yourRating;
    return [
      TextSpan(text: 'You hired ${artisan.firstName}'),
      TextSpan(text: DateFormat('d\u00A0MMM').format(hired.lastHiredOn)),
      if (rating != null)
        TextSpan(
          children: [
            TextSpan(text: 'you rated $rating'),
            TextSpan(text: '★', style: TextStyle(color: c.rating)),
          ],
        ),
    ];
  }

  String get _km => '${artisan.distanceKm.toStringAsFixed(1)}\u00A0km';

  /// What screen readers say for the whole row, in sentences.
  String _sentence(DateTime now) {
    final a = artisan;
    final hired = this.hired;
    final nextFree = a.nextFreeAt;
    final reply = a.replyMinutes;
    final jobs = a.jobsCompleted;
    final rating = hired?.yourRating;
    return [
      [a.name, a.trade, if (a.isVerified) 'verified'].join(', '),
      [
        if (a.reviewCount == 0)
          'No reviews yet'
        else
          'Rated ${a.rating.toStringAsFixed(1)} out of 5 from '
              '${a.reviewCount} ${_plural(a.reviewCount, 'review')}',
        if (jobs > 0) '$jobs ${_plural(jobs, 'job')} done',
      ].join(', '),
      if (hired != null)
        'You hired ${a.firstName} on '
            '${DateFormat('d MMMM').format(hired.lastHiredOn)}'
            '${rating == null ? '' : ' and rated the job $rating out of 5'}',
      [
        if (a.isAvailableToday)
          'Free now'
        else if (nextFree != null)
          _FreeAt.spoken(nextFree, now),
        if (showDistance)
          '${a.distanceKm.toStringAsFixed(1)} kilometres away'
        else
          'based in ${a.area}',
        if (reply != null)
          'usually replies in about $reply ${_plural(reply, 'minute')}',
      ].join(', '),
      if (hired == null) 'From ${_count.format(a.startingPrice)} naira',
    ].join('. ');
  }
}

/// Loading placeholder shaped like [ClientArtisanRow] at the default text
/// size: bars where the three lines and the price sit.
class ClientArtisanRowSkeleton extends StatelessWidget {
  const ClientArtisanRowSkeleton({super.key, this.divider = true});

  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: _minHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              _padY,
              AppSpace.gutter,
              _padY,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: AppSpace.s2),
                  child: SkeletonBox(
                    width: _photoSize,
                    height: _photoSize,
                    radius: AppRadius.md,
                  ),
                ),
                SizedBox(width: AppSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 3.w),
                      Row(
                        children: [
                          SkeletonBox(width: 128.w, height: 14.w),
                          const Spacer(),
                          SkeletonBox(width: 64.w, height: 14.w),
                        ],
                      ),
                      SizedBox(height: 8.w),
                      SkeletonBox(width: 176.w, height: 12.w),
                      SizedBox(height: 8.w),
                      SkeletonBox(width: 148.w, height: 12.w),
                      SizedBox(height: 3.w),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (divider)
          PositionedDirectional(
            start: _textStart,
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

/// The name, shortened before anything else on its line, with the
/// verified badge right after it and [trailing] at the end.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.artisan, required this.trailing});

  final Artisan artisan;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  artisan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Hugs a shortened name, so the badge follows it.
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: AppText.titleSmall.copyWith(color: c.textPrimary),
                ),
              ),
              if (artisan.isVerified) ...[
                SizedBox(width: AppSpace.s4),
                VerifiedBadge(size: 14.w),
              ],
            ],
          ),
        ),
        SizedBox(width: AppSpace.s8),
        trailing,
      ],
    );
  }
}

/// "from ₦8,000", never shortened.
class _Price extends StatelessWidget {
  const _Price({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'from ',
            style: AppText.caption.copyWith(color: c.textTertiary),
          ),
          TextSpan(text: Naira.format(amount)),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      style: AppText.labelSmall.copyWith(color: c.textPrimary),
    );
  }
}

class _BookAgainLabel extends StatelessWidget {
  const _BookAgainLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Book again',
      maxLines: 1,
      softWrap: false,
      style: AppText.labelSmall.copyWith(color: context.colors.brandText),
    );
  }
}

/// "Book again" as a link with a 48pt touch area, drawn over the name's
/// line where the price would be.
class _BookAgainLink extends StatelessWidget {
  const _BookAgainLink({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Book $name again',
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSize.minTapTarget,
          minWidth: AppSize.minTapTarget,
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _linkPad),
            child: const _BookAgainLabel(),
          ),
        ),
      ),
    );
  }
}

/// A rounded square photo: the artisan's headshot, else their work photo
/// cropped around its subject, else their initials. A green dot on the
/// corner says they're free now.
class _Photo extends StatelessWidget {
  const _Photo({required this.artisan});

  final Artisan artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = _photoSize;
    final headshot = imageFor(artisan.photo);
    final image = headshot ?? imageFor(artisan.coverPhoto);
    final initials = Center(
      child: Text(
        AppAvatar.initialsOf(artisan.name),
        style: AppText.title.copyWith(color: c.textSecondary),
      ),
    );
    final fade = context.motion(AppMotion.base);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: AppRadius.mdAll,
              child: ColoredBox(
                color: c.surfaceMuted,
                child: image == null
                    ? initials
                    : Image(
                        image: ResizeImage.resizeIfNeeded(
                          (size * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          null,
                          image,
                        ),
                        fit: BoxFit.cover,
                        alignment: headshot != null
                            ? Alignment.center
                            : Alignment(
                                artisan.coverFocusX,
                                artisan.coverFocusY,
                              ),
                        excludeFromSemantics: true,
                        frameBuilder:
                            (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: fade,
                            curve: AppMotion.standard,
                            child: child,
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => initials,
                      ),
              ),
            ),
          ),
          if (artisan.isAvailableToday)
            PositionedDirectional(
              end: -3.w,
              bottom: -3.w,
              child: Container(
                width: 16.w,
                height: 16.w,
                decoration: BoxDecoration(
                  color: c.online,
                  shape: BoxShape.circle,
                  // The page shows through as a ring, so the dot reads as
                  // its own mark on any photo.
                  border: Border.all(color: c.background, width: 2.w),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// When an artisan who isn't free now can next take a job.
abstract final class _FreeAt {
  /// "Free tomorrow 9 AM", "Free Sat 8:30 AM".
  static String short(DateTime at, DateTime now) =>
      'Free\u00A0${_day(at, now, long: false)}\u00A0${_time(at)}';

  /// "Free tomorrow at 9 AM", "Free Saturday at 8:30 AM".
  static String spoken(DateTime at, DateTime now) =>
      'Free ${_day(at, now, long: true)} at ${_time(at)}';

  static String _day(DateTime at, DateTime now, {required bool long}) {
    final days = DateTime.utc(at.year, at.month, at.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days < 7) return DateFormat(long ? 'EEEE' : 'EEE').format(at);
    return DateFormat(long ? 'd MMMM' : 'd\u00A0MMM').format(at);
  }

  /// "9 AM" on the hour, else "8:30 AM".
  static String _time(DateTime at) =>
      DateFormat(at.minute == 0 ? 'h\u00A0a' : 'h:mm\u00A0a').format(at);
}
