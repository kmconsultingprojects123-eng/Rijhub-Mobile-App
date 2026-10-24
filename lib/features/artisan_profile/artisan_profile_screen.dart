import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_launch.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// An artisan's profile, as clients see it: their work, the trust signals,
/// what they charge, and what people say. Booking is the one main action.
class ArtisanProfileScreen extends StatelessWidget {
  const ArtisanProfileScreen(
      {super.key, required this.artisanId, this.preview = false});

  final String artisanId;

  /// The artisan looking at their own profile.
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final area = context.read<SessionController>().area;
    // The profile is its own scaffold (its booking bar sits in the bottom
    // slot); the loading state gets a plain one.
    return Loader<(ArtisanProfile, Set<String>)>(
      load: () async {
        final directory = context.read<DirectoryRepository>();
        final signedIn = context.read<SessionController>().isSignedIn;
        final results = await Future.wait<Object>([
          preview
              ? context.read<ArtisanSetupRepository>().myProfile()
              : directory.profile(artisanId, area: area),
          signedIn && !preview
              ? directory.savedIds()
              : Future.value(<String>{}),
        ]);
        return (results[0] as ArtisanProfile, results[1] as Set<String>);
      },
      loading: const Scaffold(body: _ProfileSkeleton()),
      builder: (context, data, reload) => _Profile(
        profile: data.$1,
        saved: data.$2.contains(data.$1.artisan.id),
        preview: preview,
        // Your own distance from yourself means nothing.
        hasArea: area != null && !preview,
      ),
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile(
      {required this.profile,
      required this.saved,
      required this.preview,
      required this.hasArea});

  final ArtisanProfile profile;
  final bool saved;
  final bool preview;
  final bool hasArea;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  late bool _saved = widget.saved;

  Artisan get _a => widget.profile.artisan;

  Future<void> _toggleSave() async {
    final ok = await context.read<AuthGate>().ensureSignedIn(
          context,
          AuthPrompt(
              title: 'Save ${_a.firstName}',
              message:
                  'Add your phone number to keep your favourite artisans in one place.'),
        );
    if (!ok || !mounted) return;
    final now = await context.read<DirectoryRepository>().toggleSaved(_a.id);
    setState(() => _saved = now);
    if (mounted) {
      showToast(context, now ? 'Saved ${_a.firstName}' : 'Removed from saved');
    }
  }

  Future<void> _share() async {
    await Clipboard.setData(
        ClipboardData(text: 'https://rijhub.com/a/${_a.id}'));
    if (mounted) {
      showToast(context, 'Link to ${_a.firstName}\'s profile copied');
    }
  }

  Future<void> _message() async {
    final ok = await context
        .read<AuthGate>()
        .ensureSignedIn(context, AuthPrompt.messages);
    if (!ok || !mounted) return;
    final convo = await context.read<ChatRepository>().withArtisan(_a.id);
    if (mounted) context.push(Routes.chat(convo.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.profile;
    final a = _a;
    final g = AppSpace.gutter;
    final photo = imageFor(a.coverPhoto ?? a.photo);
    final heroHeight = 330.w;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: photo != null
                      ? Semantics(
                          image: true,
                          label: 'Work photo of ${a.name}',
                          child: Image(
                              image: photo,
                              fit: BoxFit.cover,
                              alignment:
                                  Alignment(a.coverFocusX, a.coverFocusY)),
                        )
                      : Container(
                          color: c.surfaceMuted,
                          alignment: Alignment.center,
                          child: AppAvatar(name: a.name, size: 96.w),
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 130.w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black
                              .withValues(alpha: photo == null ? 0 : 0.45),
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8.w,
                  right: 8.w,
                  top: MediaQuery.paddingOf(context).top + 4.w,
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: IconsaxPlusLinear.arrow_left,
                        label: 'Back',
                        onTap: () => goBack(context),
                      ),
                      const Spacer(),
                      _CircleButton(
                          icon: IconsaxPlusLinear.export_3,
                          label: 'Share profile',
                          onTap: _share),
                      if (!widget.preview)
                        _CircleButton(
                          icon: _saved
                              ? IconsaxPlusBold.heart
                              : IconsaxPlusLinear.heart,
                          label: _saved ? 'Saved' : 'Save',
                          color: _saved ? c.brand : null,
                          onTap: _toggleSave,
                        ),
                    ],
                  ),
                ),
                // The page's rounded top edge, drawn over the photo. (A
                // sliver below can't overlap it: earlier slivers paint
                // on top.)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -1,
                  height: 25.w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28.w)),
                    ),
                  ),
                ),
                if (p.work.isNotEmpty)
                  Positioned(
                    right: g,
                    bottom: 40.w,
                    child: MapPill(
                      label: '${p.work.length} photos',
                      icon: IconsaxPlusLinear.gallery,
                      onTap: () => context.push(Routes.artisanWork(a.id)),
                    ),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: ColoredBox(
              color: c.background,
              child: Padding(
                padding: EdgeInsets.fromLTRB(g, 0, g, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Semantics(
                            header: true,
                            child: Text(a.name,
                                style: AppText.headline
                                    .copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        if (a.isVerified) ...[
                          SizedBox(width: 6.w),
                          const VerifiedBadge(size: 20),
                        ],
                      ],
                    ),
                    SizedBox(height: 4.w),
                    Row(
                      children: [
                        Container(
                          width: 8.w,
                          height: 8.w,
                          decoration: BoxDecoration(
                            color: a.isAvailableToday ? c.online : c.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Flexible(
                          child: Text(
                            '${a.trade} · ${a.area}${widget.hasArea ? ' · ${a.distanceKm.toStringAsFixed(1)} km' : ''} · '
                            '${a.isAvailableToday ? 'Free today' : a.nextFreeAt != null ? 'Next free ${Schedule.dayAndTime(a.nextFreeAt!)}' : 'Busy today'}',
                            style:
                                AppText.body.copyWith(color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 18.w),
                    _Stats(profile: p),
                    SizedBox(height: 16.w),
                    _TrustStrip(artisan: a),
                    SizedBox(height: 28.w),
                    const SectionTitle('Services and prices'),
                    SizedBox(height: 4.w),
                    if (p.services.isEmpty)
                      const InlineNote(
                          title: 'No prices yet',
                          message:
                              'Ask for a quote and they will reply with a price.')
                    else
                      for (final (i, s) in p.services.indexed)
                        _ServiceRow(
                          service: s,
                          divider: i < p.services.length - 1,
                          onTap: widget.preview
                              ? null
                              : () => openAsk(context, artisanId: a.id),
                        ),
                    if (!widget.preview) ...[
                      SizedBox(height: 8.w),
                      Pressable(
                        onTap: () =>
                            openAsk(context, artisanId: a.id, text: null),
                        semanticLabel:
                            'Ask ${a.firstName} for a price for something else',
                        child: Container(
                          padding: EdgeInsets.all(14.w),
                          decoration: BoxDecoration(
                            color: c.surfaceMuted,
                            borderRadius: BorderRadius.circular(16.w),
                          ),
                          child: Row(
                            children: [
                              Icon(IconsaxPlusLinear.message_question,
                                  size: 20.w, color: c.textPrimary),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                    'Need something else? Ask ${a.firstName} for a price',
                                    style: AppText.labelSmall),
                              ),
                              Icon(IconsaxPlusLinear.arrow_right_3,
                                  size: 16.w, color: c.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (p.work.isNotEmpty) ...[
                      SizedBox(height: 28.w),
                      SectionTitle('Their work',
                          action: 'See all',
                          onAction: () =>
                              context.push(Routes.artisanWork(a.id))),
                      SizedBox(height: 8.w),
                      SizedBox(
                        height: 128.w,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: p.work.length,
                          separatorBuilder: (_, __) => SizedBox(width: 10.w),
                          itemBuilder: (context, i) {
                            final w = p.work[i];
                            return Pressable(
                              onTap: () =>
                                  context.push(Routes.artisanWork(a.id, i)),
                              semanticLabel: w.caption ?? 'Work photo ${i + 1}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16.w),
                                child: Image(
                                  image: imageFor(w.image)!,
                                  width: 128.w,
                                  height: 128.w,
                                  fit: BoxFit.cover,
                                  alignment: Alignment(w.focusX, w.focusY),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    SizedBox(height: 28.w),
                    const SectionTitle('About'),
                    SizedBox(height: 8.w),
                    if (p.about.isNotEmpty) Text(p.about, style: AppText.body),
                    SizedBox(height: 12.w),
                    if (p.businessName?.isNotEmpty ?? false)
                      _Fact(IconsaxPlusLinear.shop, p.businessName!),
                    // Optional: "0 years of experience" would only put people off.
                    if (p.experienceYears > 0)
                      _Fact(
                          IconsaxPlusLinear.medal_star,
                          p.experienceYears == 1
                              ? '1 year of experience'
                              : '${p.experienceYears} years of experience'),
                    for (final cert in p.certifications)
                      _Fact(IconsaxPlusLinear.award, cert),
                    _Fact(IconsaxPlusLinear.location,
                        'Works within ${p.serviceArea.radiusKm} km of ${p.serviceArea.area}'),
                    _Fact(IconsaxPlusLinear.clock, hoursLabel(p.hours)),
                    _Fact(IconsaxPlusLinear.message_text_1,
                        'Speaks ${p.languages.join(' and ')}'),
                    _Fact(IconsaxPlusLinear.calendar_1,
                        'On Employi since ${_monthYear(p.joinedOn)}'),
                    SizedBox(height: 28.w),
                    SectionTitle(
                      'Reviews',
                      action: p.ratings.count > p.reviews.length
                          ? 'See all ${p.ratings.count}'
                          : null,
                      onAction: () => context.push(Routes.artisanReviews(a.id)),
                    ),
                    SizedBox(height: 10.w),
                    if (p.ratings.count == 0)
                      const InlineNote(
                          title: 'No reviews yet',
                          message:
                              'Reviews come only from clients who booked and paid through Employi.')
                    else
                      // The rating and count are in the stats up top;
                      // the full breakdown is on the reviews page.
                      for (final r in p.reviews) ReviewTile(review: r),
                    SizedBox(height: 24.w),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.preview
          ? BottomBar(
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.eye,
                      size: 20.w, color: c.textSecondary),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This is how clients see you',
                            style: AppText.labelSmall),
                        Text('Fresh prices and photos get more bookings',
                            style: AppText.caption
                                .copyWith(color: c.textTertiary)),
                      ],
                    ),
                  ),
                  SizedBox(width: 10.w),
                  AppButton(
                    label: 'Edit',
                    expand: false,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push(Routes.editProfile),
                  ),
                ],
              ),
            )
          : BottomBar(
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('from',
                          style:
                              AppText.caption.copyWith(color: c.textTertiary)),
                      Text(Naira.format(a.startingPrice), style: AppText.title),
                    ],
                  ),
                  SizedBox(width: 12.w),
                  AppIconButton(
                    icon: IconsaxPlusLinear.message,
                    filled: true,
                    semanticLabel: 'Message ${a.firstName}',
                    onPressed: _message,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: AppButton(
                      label: 'Book ${a.firstName}',
                      onPressed: () => openAsk(context, artisanId: a.id),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

String _monthYear(DateTime d) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${months[d.month - 1]} ${d.year}';
}

/// "Mon–Sat, 8 AM–6 PM".
String hoursLabel(WorkingHours h) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final days = h.days.toList()..sort();
  String clock(int minutes) {
    final hour = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} ${hour < 12 || hour == 24 ? 'AM' : 'PM'}';
  }

  final span = days.length == 7
      ? 'Every day'
      : (days.length > 1 && days.last - days.first == days.length - 1)
          ? '${names[days.first - 1]}–${names[days.last - 1]}'
          : days.map((d) => names[d - 1]).join(', ');
  if (h.startMinutes == 0 && h.endMinutes >= 1439) return '$span, any time';
  return '$span, ${clock(h.startMinutes)}–${clock(h.endMinutes)}';
}

class _CircleButton extends StatelessWidget {
  const _CircleButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48.w,
            height: 48.w,
            child: Center(
              child: Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 20.w, color: color ?? const Color(0xFF171717)),
              ),
            ),
          ),
        ),
      );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.profile});

  final ArtisanProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = profile.artisan;
    Widget cell(String top, String bottom, {IconData? icon}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16.w, color: c.rating),
                    SizedBox(width: 4.w),
                  ],
                  Flexible(
                      child: Text(top,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title)),
                ],
              ),
              SizedBox(height: 2.w),
              Text(bottom,
                  style: AppText.caption.copyWith(color: c.textSecondary)),
            ],
          ),
        );
    Widget rule() => Container(
        width: 1,
        height: 34.w,
        color: c.border,
        margin: EdgeInsets.symmetric(horizontal: 12.w));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.w),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          cell(
              a.reviewCount == 0 ? 'New' : a.rating.toStringAsFixed(1),
              a.reviewCount == 0
                  ? 'No reviews yet'
                  : a.reviewCount == 1
                      ? '1 review'
                      : '${a.reviewCount} reviews',
              icon: a.reviewCount == 0 ? null : IconsaxPlusBold.star_1),
          rule(),
          cell('${a.jobsCompleted}',
              a.jobsCompleted == 1 ? 'job done' : 'jobs done'),
          // How fast they reply, once there is something to measure: an
          // unknown rate is not 0%.
          if (a.replyMinutes != null || profile.responseRate != null) ...[
            rule(),
            cell(
              a.replyMinutes == null
                  ? '${profile.responseRate}%'
                  : '~${a.replyMinutes} min',
              a.replyMinutes == null ? 'reply rate' : 'to reply',
            ),
          ],
        ],
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip({required this.artisan});

  final Artisan artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(IconData icon, String text, Color color) => Expanded(
          child: Row(
            children: [
              Icon(icon, size: 18.w, color: color),
              SizedBox(width: 6.w),
              Expanded(
                  child: Text(text,
                      style: AppText.bodySmall.copyWith(
                          color: c.textPrimary, fontWeight: FontWeight.w500))),
            ],
          ),
        );
    return Row(
      children: [
        if (artisan.isVerified)
          item(IconsaxPlusBold.verify, 'ID checked', c.verified),
        item(IconsaxPlusBold.shield_tick, 'Payment protected', c.success),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.divider, this.onTap});

  final ServiceOffer service;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final price = service.priceMax == null
        ? Naira.format(service.price)
        : Naira.range(service.price, service.priceMax);
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: 14.w),
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.border)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w500)),
                if (service.unit != null)
                  Text(service.unit!,
                      style: AppText.caption.copyWith(color: c.textTertiary)),
              ],
            ),
          ),
          Text(price, style: AppText.labelSmall),
          if (onTap != null) ...[
            SizedBox(width: 6.w),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 16.w, color: c.textTertiary),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel: '${service.name}, $price. Book',
      child: row,
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.w),
      child: Row(
        children: [
          Icon(icon, size: 18.w, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(child: Text(text, style: AppText.body)),
        ],
      ),
    );
  }
}

/// The average, the stars, and how the reviews split.
class RatingSummaryView extends StatelessWidget {
  const RatingSummaryView({super.key, required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = summary.count == 0 ? 1 : summary.count;
    return Row(
      children: [
        Column(
          children: [
            Text(summary.average.toStringAsFixed(1),
                style: AppText.display.copyWith(fontWeight: FontWeight.w800)),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= summary.average.round()
                        ? IconsaxPlusBold.star_1
                        : IconsaxPlusLinear.star_1,
                    size: 14.w,
                    color: c.rating,
                  ),
              ],
            ),
            SizedBox(height: 2.w),
            Text(summary.count == 1 ? '1 review' : '${summary.count} reviews',
                style: AppText.caption.copyWith(color: c.textSecondary)),
          ],
        ),
        SizedBox(width: 20.w),
        Expanded(
          child: Column(
            children: [
              for (var s = 5; s >= 1; s--)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 2.w),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 12.w,
                          child: Text('$s',
                              style: AppText.caption
                                  .copyWith(color: c.textSecondary))),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadius.pillAll,
                          child: LinearProgressIndicator(
                            value: (summary.byStars[s] ?? 0) / total,
                            minHeight: 6.w,
                            backgroundColor: c.surfaceMuted,
                            color: c.rating,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One review: who, the stars, when, what for, and what they said.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.w),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                  name: review.authorName,
                  image: imageFor(review.authorPhoto),
                  size: 32.w),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.authorName, style: AppText.labelSmall),
                    Text(
                      '${review.serviceName ?? ''}${review.serviceName == null ? '' : ' · '}${RelativeTime.short(review.at)}',
                      style: AppText.caption.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(
                        i <= review.rating
                            ? IconsaxPlusBold.star_1
                            : IconsaxPlusLinear.star_1,
                        size: 13.w,
                        color: c.rating),
                ],
              ),
            ],
          ),
          if (review.text != null) ...[
            SizedBox(height: 8.w),
            Text(review.text!, style: AppText.body),
          ],
          if (review.reply != null) ...[
            SizedBox(height: 8.w),
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(12.w)),
              child: Text('Reply: ${review.reply}',
                  style: AppText.bodySmall.copyWith(color: c.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonPulse(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            SkeletonBox(height: 330.w, radius: 0),
            Padding(
              padding: EdgeInsets.all(AppSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 200.w, height: 26.w),
                  SizedBox(height: 10.w),
                  SkeletonBox(width: 240.w, height: 14.w),
                  SizedBox(height: 20.w),
                  SkeletonBox(height: 70.w, radius: 18.w),
                ],
              ),
            ),
          ],
        ),
      );
}

/// All of an artisan's reviews.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, required this.artisanId, this.own = false});

  final String artisanId;

  /// The artisan's own reviews.
  final bool own;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: own ? 'Your reviews' : 'Reviews',
      body: Loader<(ArtisanProfile, List<Review>)>(
        load: () async {
          final directory = context.read<DirectoryRepository>();
          final setup = context.read<ArtisanSetupRepository>();
          final profile = own
              ? await setup.myProfile()
              : await directory.profile(artisanId);
          final reviews = await directory.reviews(profile.artisan.id);
          return (profile, reviews);
        },
        builder: (context, data, reload) => ListView(
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, 8.w, AppSpace.gutter, AppSpace.s32),
          children: [
            if (data.$1.ratings.count == 0)
              const EmptyState(
                icon: IconsaxPlusLinear.star_1,
                title: 'No reviews yet',
                message: 'Reviews appear after clients confirm a job is done.',
              )
            else ...[
              RatingSummaryView(summary: data.$1.ratings),
              SizedBox(height: 12.w),
              for (final r in data.$2) ReviewTile(review: r),
            ],
          ],
        ),
      ),
    );
  }
}

/// An artisan's work photos, full screen: swipe between them, pinch to
/// zoom.
class WorkGalleryScreen extends StatefulWidget {
  const WorkGalleryScreen(
      {super.key, required this.artisanId, this.initial = 0});

  final String artisanId;
  final int initial;

  @override
  State<WorkGalleryScreen> createState() => _WorkGalleryScreenState();
}

class _WorkGalleryScreenState extends State<WorkGalleryScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Loader<ArtisanProfile>(
          load: () =>
              context.read<DirectoryRepository>().profile(widget.artisanId),
          loading: const Center(
              child: CircularProgressIndicator(color: Colors.white)),
          builder: (context, p, _) => SafeArea(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: p.work.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image(
                          image: imageFor(p.work[i].image)!,
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  left: 4.w,
                  top: 4.w,
                  child: AppIconButton(
                    icon: IconsaxPlusLinear.close_circle,
                    semanticLabel: 'Close',
                    iconColor: Colors.white,
                    onPressed: () => goBack(context),
                  ),
                ),
                Positioned(
                  right: AppSpace.gutter,
                  top: 16.w,
                  child: Text(
                    '${_index + 1} / ${p.work.length}',
                    style: AppText.labelSmall.copyWith(color: Colors.white),
                  ),
                ),
                if (p.work.isNotEmpty && p.work[_index].caption != null)
                  Positioned(
                    left: AppSpace.gutter,
                    right: AppSpace.gutter,
                    bottom: 20.w,
                    child: Text(
                      p.work[_index].caption!,
                      style: AppText.body.copyWith(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
