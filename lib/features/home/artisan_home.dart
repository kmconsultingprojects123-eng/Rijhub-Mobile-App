import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../artisan/availability_sheet.dart';
import '../artisan/request_card.dart';
import '../location/area_pill.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// The artisan's home: status and the week in one line, the next job, the
/// requests waiting (as messages), and jobs nearby on the map. Guests see
/// the jobs first, with one way in.
class ArtisanHome extends StatelessWidget {
  const ArtisanHome({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Loader<_Data>(
          reloadOn: session,
          load: () => _Data.load(context),
          loading: const ListSkeleton(rows: 6),
          builder: (context, data, reload) => RefreshIndicator(
            color: context.colors.brandStroke,
            onRefresh: reload,
            child: _Body(data: data, reload: reload),
          ),
        ),
      ),
    );
  }
}

class _Data {
  _Data({
    required this.signedIn,
    required this.area,
    required this.dashboard,
    required this.bookings,
    required this.requests,
    required this.priceRequests,
    required this.jobs,
    required this.demand,
  });

  final bool signedIn;
  final String? area;
  final ArtisanDashboard? dashboard;
  final List<Booking> bookings;
  final List<DirectRequest> requests;
  final List<ClientJob> priceRequests;
  final List<JobPost> jobs;
  final JobDemand demand;

  static Future<_Data> load(BuildContext context) async {
    final session = context.read<SessionController>();
    final signedIn = session.isSignedIn;
    final area = session.area;
    final trades = session.tradeIds;
    final r = await Future.wait<Object?>([
      signedIn
          ? context.read<ArtisanDashboardRepository>().dashboard()
          : Future.value(null),
      signedIn
          ? context.read<BookingRepository>().upcoming(as: UserRole.artisan)
          : Future.value(<Booking>[]),
      signedIn
          ? context.read<ArtisanDashboardRepository>().requests()
          : Future.value(<DirectRequest>[]),
      signedIn
          ? context.read<QuoteRepository>().quoteRequests()
          : Future.value(<ClientJob>[]),
      context.read<JobRepository>().openJobsNearby(
            area: area ?? AreaPill.city,
            categoryIds: trades.isEmpty ? null : trades.toSet(),
            limit: 8,
          ),
      context
          .read<JobRepository>()
          .demand(area: area, categoryId: trades.isEmpty ? null : trades.first),
    ]);
    return _Data(
      signedIn: signedIn,
      area: area,
      dashboard: r[0] as ArtisanDashboard?,
      bookings: r[1]! as List<Booking>,
      requests: r[2]! as List<DirectRequest>,
      priceRequests: r[3]! as List<ClientJob>,
      jobs: r[4]! as List<JobPost>,
      demand: r[5]! as JobDemand,
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.data, required this.reload});

  final _Data data;
  final Future<void> Function() reload;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  String? _answering;

  Future<void> _toggle(ArtisanDashboard dash) async {
    final on = dash.availability != AvailabilityStatus.available;
    await context.read<ArtisanDashboardRepository>().setAvailability(on);
    await widget.reload();
    if (mounted) {
      showToast(
          context,
          on
              ? "You're available. Requests will come to you."
              : "You're off. No new requests until you switch on.");
    }
  }

  Future<void> _accept(DirectRequest r) async {
    setState(() => _answering = r.id);
    final repo = context.read<ArtisanDashboardRepository>();
    try {
      final booking = await repo.respond(r.id, accept: true);
      if (!mounted) return;
      showToast(
          context, 'Booked. ${r.clientName.split(' ').first} has been told.');
      if (booking != null) await context.push(Routes.booking(booking.id));
    } on RequestExpiredException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _answering = null);
      await widget.reload();
    }
  }

  Future<void> _reply(DirectRequest r) async {
    final convos = await context.read<ChatRepository>().conversations();
    if (!mounted) return;
    final match =
        convos.where((c) => c.title.startsWith(r.clientName.split(' ').first));
    if (match.isNotEmpty) {
      context.push(Routes.chat(match.first.id));
    } else {
      context.push(Routes.request(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final c = context.colors;
    final g = AppSpace.gutter;
    final dash = d.dashboard;
    final next = d.bookings
        .where((b) => b.status != BookingStatus.requested)
        .firstOrNull;
    final nextStep = dash?.setupSteps.where((s) => !s.done).firstOrNull;
    final trades = context.read<SessionController>().tradeIds;
    return ListView(
      padding: EdgeInsets.only(bottom: AppSpace.s32),
      children: [
        SizedBox(height: 8.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: d.signedIn && dash != null
              ? _Header(
                  dash: dash,
                  onToggle: () => _toggle(dash),
                  reload: widget.reload)
              : const _GuestHeader(),
        ),
        if (!d.signedIn) ...[
          SizedBox(height: 18.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: Text(
              'Jobs near you',
              style: AppText.display.copyWith(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8),
            ),
          ),
          SizedBox(height: 4.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: Text(
              '${d.demand.openThisWeek} open this week'
              '${d.demand.typicalBudgetMin == null ? '' : ' · most pay ${Naira.range(d.demand.typicalBudgetMin, d.demand.typicalBudgetMax)}'}',
              style: AppText.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
        if (nextStep != null) ...[
          SizedBox(height: 14.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: _SetupRow(
                step: nextStep,
                done: dash!.setupDone,
                total: dash.setupSteps.length),
          ),
        ],
        if (next != null) ...[
          SizedBox(height: 14.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: _NextJob(booking: next),
          ),
        ],
        if (d.requests.isNotEmpty || d.priceRequests.isNotEmpty) ...[
          SizedBox(height: 24.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: SectionTitle('Requests',
                count: d.requests.length + d.priceRequests.length),
          ),
          for (final r in d.requests)
            Padding(
              padding: EdgeInsets.fromLTRB(g, 8.w, g, 4.w),
              child: RequestMessageCard(
                request: r,
                busy: _answering == r.id,
                onAccept: () => _accept(r),
                onReply: () => _reply(r),
                onOpen: () async {
                  await context.push(Routes.request(r.id));
                  await widget.reload();
                },
              ),
            ),
          for (final j in d.priceRequests)
            Padding(
              padding: EdgeInsets.fromLTRB(g, 8.w, g, 4.w),
              child: PriceRequestCard(
                job: j,
                onQuote: () async {
                  await context.push(Routes.quoteRequest(j.id));
                  await widget.reload();
                },
              ),
            ),
        ] else if (d.signedIn &&
            dash != null &&
            dash.availability == AvailabilityStatus.available) ...[
          SizedBox(height: 16.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: const InlineNote(
              icon: IconsaxPlusLinear.notification,
              title: 'No requests right now',
              message:
                  "You're available, so we'll tell you the moment a client asks for you.",
            ),
          ),
        ],
        SizedBox(height: 24.w),
        if (d.signedIn)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: SectionTitle(
              trades.isEmpty ? 'Jobs near you' : 'Jobs for you',
              action: 'Open map',
              onAction: () => context.go('${Routes.explore}?map=1'),
            ),
          ),
        if (d.signedIn) SizedBox(height: 8.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: _JobsMap(jobs: d.jobs, area: d.area),
        ),
        SizedBox(height: 4.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: Column(
            children: [
              for (final (i, j) in d.jobs.take(4).indexed)
                JobTile(
                  job: j,
                  hasArea: d.area != null,
                  divider: i < 3,
                  onTap: () => context.push(Routes.job(j.id)),
                ),
            ],
          ),
        ),
        SizedBox(height: 8.w),
        Center(
          child: AppButton(
            label: 'See all ${d.demand.openThisWeek} jobs',
            variant: AppButtonVariant.tertiary,
            expand: false,
            onPressed: () => context.go(Routes.explore),
          ),
        ),
        if (!d.signedIn) ...[
          SizedBox(height: 8.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: _JoinBar(
                onJoin: () => context
                    .read<AuthGate>()
                    .ensureSignedIn(context, AuthPrompt.joinAsArtisan)),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.dash, required this.onToggle, required this.reload});

  final ArtisanDashboard dash;
  final VoidCallback onToggle;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.watch<SessionController>().user!;
    final (label, color) = switch (dash.availability) {
      AvailabilityStatus.available => ('Available', c.success),
      AvailabilityStatus.busy => (
          'Busy until ${Schedule.time(dash.busyUntil!)}',
          c.warning
        ),
      AvailabilityStatus.off => ('Off', c.textTertiary),
    };
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Your profile',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => context.go(Routes.account),
            child: AppAvatar(
                name: user.fullName, image: imageFor(user.photo), size: 42.w),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Semantics(
            button: true,
            label:
                '$label. ${Naira.format(dash.earningsThisWeek)} this week. Change availability',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final changed =
                    await showAvailabilitySheet(context, current: dash);
                if (changed != null) await reload();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleSmall
                          .copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(height: 1.w),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: label,
                          style: AppText.bodySmall.copyWith(
                              color: color, fontWeight: FontWeight.w600)),
                      TextSpan(
                        text:
                            ' · ${Naira.format(dash.earningsThisWeek)} this week',
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          toggled: dash.availability == AvailabilityStatus.available,
          label: 'Available for bookings',
          child: Transform.scale(
            scale: 0.86,
            child: Switch.adaptive(
              value: dash.availability == AvailabilityStatus.available,
              activeTrackColor: c.success,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => onToggle(),
            ),
          ),
        ),
        CountStream(
          stream: context.read<NoticeRepository>().unreadCount(),
          builder: (context, unread) => AppIconButton(
            icon: IconsaxPlusLinear.notification,
            showBadge: unread > 0,
            semanticLabel: 'Notifications',
            onPressed: () => context.push(Routes.notifications),
          ),
        ),
      ],
    );
  }
}

class _GuestHeader extends StatelessWidget {
  const _GuestHeader();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const RijHubLogo(height: 24),
          const Spacer(),
          const AreaPill(),
          SizedBox(width: 4.w),
          AppButton(
            label: 'Sign in',
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.small,
            expand: false,
            onPressed: () => context
                .read<AuthGate>()
                .ensureSignedIn(context, AuthPrompt.signIn),
          ),
        ],
      );
}

class _SetupRow extends StatelessWidget {
  const _SetupRow(
      {required this.step, required this.done, required this.total});

  final SetupStep step;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final route = switch (step.id) {
      'identity' => Routes.verification,
      'services' => Routes.services,
      'work_photos' => Routes.portfolio,
      'area' => Routes.workArea,
      'payout' => Routes.payoutAccount,
      _ => Routes.account,
    };
    final urgent = step.blocksBookings;
    return Pressable(
      onTap: () => context.push(route),
      semanticLabel:
          '${step.label}. ${step.reason ?? ''}. Step ${done + 1} of $total',
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: urgent ? c.brandSubtle : c.surfaceMuted,
          borderRadius: BorderRadius.circular(16.w),
          border: urgent ? Border.all(color: c.brandSubtleBorder) : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38.w,
              height: 38.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: done / total,
                    strokeWidth: 3,
                    backgroundColor: c.border,
                    color: c.brandStroke,
                  ),
                  Text('$done/$total',
                      style: AppText.caption.copyWith(
                          fontSize: 10.sp, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.label, style: AppText.labelSmall),
                  if (step.reason != null)
                    Text(
                      urgent
                          ? 'Clients can book you once this is done. ${step.effort ?? ''}'
                          : step.reason!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 16.w, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _NextJob extends StatelessWidget {
  const _NextJob({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = b.scheduledAt;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final until = t.difference(DateTime.now());
    final soon = until.isNegative
        ? 'now'
        : until.inHours >= 1
            ? 'in ${until.inHours} h ${until.inMinutes % 60}'
            : 'in ${until.inMinutes} min';
    final today = Schedule.dayLabel(t) == 'Today';
    return LiveBar(
      height: 66,
      leading: TimeChip(
          time: '$h:${t.minute.toString().padLeft(2, '0')}',
          period: t.hour < 12 ? 'AM' : 'PM'),
      title:
          '${b.serviceName} · ${b.counterpartName.split(' ').first} ${b.counterpartName.split(' ').length > 1 ? '${b.counterpartName.split(' ')[1][0]}.' : ''}',
      subtitle:
          '${b.area}${b.distanceKm == null ? '' : ' · ${b.distanceKm!.toStringAsFixed(1)} km'} · ${today ? soon : Schedule.dayLabel(t)}',
      onTap: () => context.push(Routes.booking(b.id)),
      trailing: RoundAction(
        icon: IconsaxPlusLinear.routing_2,
        label: 'Directions',
        onTap: () {
          final q = Uri.encodeComponent('${b.landmark ?? ''} ${b.area}, Abuja');
          launchUrl(
              Uri.parse(
                  'https://www.google.com/maps/dir/?api=1&destination=$q'),
              mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
}

class _JobsMap extends StatelessWidget {
  const _JobsMap({required this.jobs, required this.area});

  final List<JobPost> jobs;
  final String? area;

  @override
  Widget build(BuildContext context) {
    final centre = AbujaPlaces.centreOf(area);
    return Pressable(
      onTap: () => context.go('${Routes.explore}?map=1'),
      semanticLabel: 'Map of ${jobs.length} jobs near you. Open map',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.w),
        child: SizedBox(
          height: 160.w,
          child: RijMap(
            lat: centre.lat,
            lng: centre.lng,
            kmAcross: area == null ? 12 : 6,
            fit: area == null,
            showMe: area != null,
            markers: [
              for (final j in jobs.take(6))
                if (j.location != null)
                  MapMarker(
                    lat: j.location!.lat,
                    lng: j.location!.lng,
                    child: PricePin(pinPrice(j), urgent: j.isUrgent),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinBar extends StatelessWidget {
  const _JoinBar({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.w, 12.w, 12.w),
      decoration: BoxDecoration(
          color: c.surfaceStrong, borderRadius: BorderRadius.circular(18.w)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ready to quote?',
                    style:
                        AppText.titleSmall.copyWith(color: c.onSurfaceStrong)),
                Text('Free. Just your phone number.',
                    style: AppText.bodySmall.copyWith(
                        color: c.onSurfaceStrong.withValues(alpha: 0.65))),
              ],
            ),
          ),
          AppButton(
              label: 'Join free',
              size: AppButtonSize.small,
              expand: false,
              onPressed: onJoin),
        ],
      ),
    );
  }
}

/// The trades shown on the home's job list, for screen readers.
String tradesLabel(List<String> ids) =>
    ids.map((id) => Trades.byId(id).name).join(', ');
