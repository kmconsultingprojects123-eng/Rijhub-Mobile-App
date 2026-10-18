import 'package:flutter/material.dart';
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
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_launch.dart';
import '../location/area_pill.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// The client's home, Ask first: say what's wrong (words, a photo or a
/// voice note), then the booking under way, top-rated artisans as photos,
/// and who's free on the map.
class ClientHome extends StatelessWidget {
  const ClientHome({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Loader<_HomeData>(
          reloadOn: session,
          load: () => _HomeData.load(context),
          loading: const _HomeSkeleton(),
          builder: (context, data, reload) => RefreshIndicator(
            color: context.colors.brandStroke,
            onRefresh: reload,
            child: _HomeBody(data: data),
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  _HomeData({
    required this.area,
    required this.upcoming,
    required this.topRated,
    required this.freeNow,
    required this.jobs,
    required this.saved,
  });

  final String? area;
  final List<Booking> upcoming;
  final List<Artisan> topRated;
  final List<Artisan> freeNow;
  final List<ClientJob> jobs;
  final Set<String> saved;

  static Future<_HomeData> load(BuildContext context) async {
    final session = context.read<SessionController>();
    final artisans = context.read<ArtisanRepository>();
    final area = session.area;
    final city = area ?? AreaPill.city;
    final signedIn = session.isSignedIn;
    final results = await Future.wait<Object>([
      signedIn
          ? context.read<BookingRepository>().upcoming(as: UserRole.client)
          : Future.value(<Booking>[]),
      artisans.topRatedNearby(area: city, limit: 8),
      artisans.topRatedNearby(area: city, freeNow: true, limit: 14),
      signedIn
          ? context.read<ClientJobRepository>().mine()
          : Future.value(<ClientJob>[]),
      signedIn
          ? context.read<DirectoryRepository>().savedIds()
          : Future.value(<String>{}),
    ]);
    return _HomeData(
      area: area,
      upcoming: results[0] as List<Booking>,
      topRated: results[1] as List<Artisan>,
      freeNow: results[2] as List<Artisan>,
      jobs: results[3] as List<ClientJob>,
      saved: results[4] as Set<String>,
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({required this.data});

  final _HomeData data;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  late Set<String> _saved = widget.data.saved;

  @override
  void didUpdateWidget(covariant _HomeBody old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _saved = widget.data.saved;
  }

  Future<void> _toggleSave(Artisan a) async {
    final ok = await context.read<AuthGate>().ensureSignedIn(
        context,
        AuthPrompt(
            title: 'Save ${a.firstName}',
            message:
                'Add your phone number to keep your favourite artisans in one place.'));
    if (!ok || !mounted) return;
    final now = await context.read<DirectoryRepository>().toggleSaved(a.id);
    setState(() => now ? _saved.add(a.id) : _saved.remove(a.id));
    if (mounted) {
      showToast(context,
          now ? 'Saved ${a.firstName}' : 'Removed ${a.firstName} from saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final gutter = AppSpace.gutter;
    final hasArea = d.area != null;
    final booking = d.upcoming.isEmpty ? null : d.upcoming.first;
    final quoting = d.jobs
        .where((j) => j.status == JobStatus.open && j.pendingQuotes > 0)
        .toList();

    return ListView(
      padding: EdgeInsets.only(bottom: AppSpace.s32),
      children: [
        SizedBox(height: 8.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: const _Header(),
        ),
        SizedBox(height: 14.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Semantics(
            header: true,
            child: Text(
              'What needs fixing?',
              style: AppText.display.copyWith(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8),
            ),
          ),
        ),
        SizedBox(height: 14.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: AskBar(
            onTap: () => openAsk(context),
            onCamera: () => openAsk(context, start: AskStart.camera),
            onMic: () => openAsk(context, start: AskStart.voice),
          ),
        ),
        SizedBox(height: 6.w),
        ChipRow(children: [
          for (final (text, key) in commonProblems)
            PromptChip(
              label: text,
              icon: categoryIcon(key),
              onTap: () => openAsk(context, text: text),
            ),
        ]),
        if (booking != null) ...[
          SizedBox(height: 12.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: _BookingBar(booking: booking),
          ),
        ],
        if (quoting.isNotEmpty) ...[
          SizedBox(height: 10.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: _QuotesRow(job: quoting.first),
          ),
        ],
        SizedBox(height: 24.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: SectionTitle(
            hasArea ? 'Top-rated near you' : 'Top-rated in Abuja',
            action: 'See all',
            onAction: () => context.go(Routes.explore),
          ),
        ),
        SizedBox(height: 8.w),
        SizedBox(
          height: 200.w,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: d.topRated.length,
            separatorBuilder: (_, __) => SizedBox(width: 12.w),
            itemBuilder: (context, i) {
              final a = d.topRated[i];
              return ArtisanPhotoCard(
                artisan: a,
                hasArea: hasArea,
                saved: _saved.contains(a.id),
                onSave: () => _toggleSave(a),
                onTap: () => context.push(Routes.artisan(a.id)),
              );
            },
          ),
        ),
        SizedBox(height: 16.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: _FreeMap(area: d.area, artisans: d.freeNow),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.watch<SessionController>();
    final user = session.user;
    return Row(
      children: [
        if (user != null) ...[
          Semantics(
            button: true,
            label: 'Your profile',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => context.go(Routes.account),
              child: AppAvatar(
                  name: user.fullName, image: imageFor(user.photo), size: 40.w),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Greeting.forTime(DateTime.now()),
                    style: AppText.caption.copyWith(color: c.textTertiary)),
                Text(user.firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ] else ...[
          const RijHubLogo(height: 24),
          const Spacer(),
        ],
        const AreaPill(),
        SizedBox(width: 4.w),
        if (user == null)
          AppButton(
            label: 'Sign in',
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.small,
            expand: false,
            onPressed: () => context
                .read<AuthGate>()
                .ensureSignedIn(context, AuthPrompt.join),
          )
        else
          CountStream(
            stream: context.read<NoticeRepository>().unreadCount(),
            builder: (context, unread) => AppIconButton(
              icon: IconsaxPlusLinear.notification,
              filled: true,
              showBadge: unread > 0,
              semanticLabel: 'Notifications',
              onPressed: () => context.push(Routes.notifications),
            ),
          ),
      ],
    );
  }
}

/// The booking under way, as a dark bar: who, when, and how it's going.
class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final first = booking.counterpartName.split(' ').first;
    final when = Schedule.dayAndTime(booking.scheduledAt);
    final (title, sub) = switch (booking.status) {
      BookingStatus.requested => (
          'Waiting for $first to accept',
          '${booking.serviceName} · $when'
        ),
      BookingStatus.onTheWay => (
          '$first is on the way',
          '${booking.serviceName} · about ${booking.etaMinutes ?? 15} min away'
        ),
      BookingStatus.inProgress => ('$first is on the job', booking.serviceName),
      BookingStatus.completed => ('Is the job done?', 'Confirm to pay $first'),
      // The day up top, the time beside the job, so neither gets cut off.
      _ => (
          '$first arrives ${switch (Schedule.dayLabel(booking.scheduledAt)) {
            'Today' => 'today',
            'Tomorrow' => 'tomorrow',
            final day => 'on $day',
          }}',
          '${Schedule.time(booking.scheduledAt)} · ${booking.serviceName}',
        ),
    };
    return LiveBar(
      leading: AppAvatar(
          name: booking.counterpartName,
          image: imageFor(booking.counterpartPhoto),
          size: 40.w),
      title: title,
      subtitle: sub,
      actionLabel: booking.status == BookingStatus.onTheWay ? 'Track' : 'View',
      onTap: () => context.push(Routes.booking(booking.id)),
    );
  }
}

class _QuotesRow extends StatelessWidget {
  const _QuotesRow({required this.job});

  final ClientJob job;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = job.pendingQuotes;
    return Pressable(
      onTap: () => context.push(Routes.clientJob(job.id)),
      semanticLabel: '$n quotes for ${job.title}. Compare',
      child: Container(
        height: 60.w,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: c.brandSubtle,
          borderRadius: BorderRadius.circular(18.w),
          border: Border.all(color: c.brandSubtleBorder),
        ),
        child: Row(
          children: [
            FaceStack(people: [
              for (final q in job.quotes.take(3))
                (q.artisan.name, q.artisan.photo)
            ], size: 26),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$n quote${n == 1 ? '' : 's'} for your job',
                      style: AppText.titleSmall),
                  Text(job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.bodySmall.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            Text('Compare',
                style: AppText.labelSmall.copyWith(color: c.brandText)),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 16.w, color: c.brandText),
          ],
        ),
      ),
    );
  }
}

/// Who is free right now, on a small map of the area.
class _FreeMap extends StatelessWidget {
  const _FreeMap({required this.area, required this.artisans});

  final String? area;
  final List<Artisan> artisans;

  @override
  Widget build(BuildContext context) {
    final centre = AbujaPlaces.centreOf(area);
    final near = area == null
        ? artisans
        : artisans.where((a) => a.distanceKm <= 3.5).toList();
    final count = near.length;
    return Pressable(
      onTap: () => context.push(Routes.map),
      semanticLabel:
          'Map: $count artisans free ${area == null ? 'in Abuja' : 'within 3 km'}. Open map',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.w),
        child: SizedBox(
          height: 170.w,
          child: Stack(
            children: [
              Positioned.fill(
                child: RijMap(
                  lat: centre.lat,
                  lng: centre.lng,
                  kmAcross: area == null ? 14 : 6,
                  fit: area == null,
                  showMe: area != null,
                  // A handful of faces reads at a glance; the full map has
                  // everyone.
                  markers: [
                    for (final a
                        in near.where((a) => a.location != null).take(6))
                      MapMarker(
                        lat: a.location!.lat,
                        lng: a.location!.lng,
                        child: FacePin(
                            name: a.name, photo: a.photo, size: 32, free: true),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 12.w,
                top: 12.w,
                child: MapPill(
                  label: area == null
                      ? '$count free in Abuja'
                      : '$count free within 3 km',
                  dotColor: context.colors.online,
                ),
              ),
              Positioned(
                right: 12.w,
                top: 12.w,
                child: const MapPill(
                    label: 'Open map', icon: IconsaxPlusLinear.map),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final g = AppSpace.gutter;
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: g, vertical: 8.w),
        children: [
          Row(children: [
            SkeletonBox(width: 40.w, height: 40.w, radius: 20.w),
            SizedBox(width: 10.w),
            SkeletonBox(width: 120.w, height: 16.w),
          ]),
          SizedBox(height: 20.w),
          SkeletonBox(width: 230.w, height: 28.w),
          SizedBox(height: 16.w),
          SkeletonBox(height: 56.w, radius: 28.w),
          SizedBox(height: 16.w),
          Row(children: [
            SkeletonBox(width: 120.w, height: 38.w, radius: 19.w),
            SizedBox(width: 8.w),
            SkeletonBox(width: 100.w, height: 38.w, radius: 19.w),
          ]),
          SizedBox(height: 28.w),
          SkeletonBox(width: 180.w, height: 18.w),
          SizedBox(height: 12.w),
          Row(children: [
            SkeletonBox(width: 236.w, height: 200.w, radius: 22.w),
            SizedBox(width: 12.w),
            Expanded(child: SkeletonBox(height: 200.w, radius: 22.w)),
          ]),
        ],
      ),
    );
  }
}
