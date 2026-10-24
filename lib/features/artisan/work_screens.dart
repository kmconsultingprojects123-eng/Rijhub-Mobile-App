import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/push.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/live_updates.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_flow.dart';
import '../booking/booking_sheets.dart';
import '../booking/checkout.dart';
import '../bookings/bookings_tab.dart';
import '../location/area_pill.dart';
import '../shared/cards.dart';
import '../shared/page.dart';
import '../shared/voice.dart';
import 'request_card.dart';
import 'verification_screen.dart';

// ---------------------------------------------------------------- request

/// A booking request, in full: what the client said and showed, when and
/// where, and the answer.
class RequestScreen extends StatelessWidget {
  const RequestScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    return Loader<DirectRequest?>(
      load: () async {
        final all = await context.read<ArtisanDashboardRepository>().requests();
        return all.where((r) => r.id == requestId).firstOrNull;
      },
      loading: const Scaffold(body: ListSkeleton()),
      builder: (context, r, _) => r == null
          ? PageScaffold(
              title: 'Request',
              body: Center(
                child: EmptyState(
                  icon: IconsaxPlusLinear.clock,
                  title: 'This request has ended',
                  message:
                      'It was answered or it expired, so the client has been offered other artisans.',
                  action: AppButton(
                      label: 'See jobs near you',
                      expand: false,
                      onPressed: () => context.go(Routes.explore)),
                ),
              ),
            )
          : _RequestView(request: r),
    );
  }
}

class _RequestView extends StatefulWidget {
  const _RequestView({required this.request});

  final DirectRequest request;

  @override
  State<_RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<_RequestView> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    final r = widget.request;
    if (!accept) {
      // Just a check: the reason chips that were here were never sent.
      final sure = await confirmSheet(
        context,
        title: 'Decline this request?',
        message: "We'll offer ${r.clientName.split(' ').first} someone else.",
        confirm: 'Decline',
        cancel: 'Keep it',
      );
      if (!sure || !mounted) return;
    }
    setState(() => _busy = true);
    final repo = context.read<ArtisanDashboardRepository>();
    try {
      final booking = await repo.respond(r.id, accept: accept);
      if (!mounted) return;
      if (accept && booking != null) {
        showToast(context, 'Booked. It\'s on your schedule.');
        context.pushReplacement(Routes.booking(booking.id));
      } else {
        showToast(context, 'Declined. We\'ll offer the client someone else.');
        goBack(context);
      }
    } on RequestExpiredException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.request;
    final left = minutesLeft(r.expiresAt);
    final centre = AbujaPlaces.centreOf(r.area);
    return PageScaffold(
      title: r.serviceName,
      subtitle: 'Request from ${r.clientName}',
      bottom: Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Decline',
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : () => _answer(false),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            flex: 2,
            child: AppButton(
              label: 'Accept · ${Naira.format(r.price)}',
              isLoading: _busy,
              onPressed: _busy ? null : () => _answer(true),
            ),
          ),
        ],
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
                color: c.warningSubtle,
                borderRadius: BorderRadius.circular(14.w)),
            child: Row(
              children: [
                Icon(IconsaxPlusLinear.timer_1, size: 20.w, color: c.warning),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'Answer within $left min, or we offer the client someone else.',
                    style: AppText.bodySmall.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 18.w),
          Row(
            children: [
              AppAvatar(
                  name: r.clientName,
                  image: imageFor(r.clientPhoto),
                  size: 48.w),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.clientName, style: AppText.title),
                    Text('Phone verified · first booking with you',
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (r.message != null) ...[
            SizedBox(height: 14.w),
            ChatBubble(text: r.message!),
          ],
          if (r.voiceNote != null) PlayableVoiceNote(note: r.voiceNote!),
          for (final p in r.photos) PhotoBubble(image: p),
          SizedBox(height: 10.w),
          InfoLine(
              icon: IconsaxPlusLinear.calendar_1,
              label: 'When',
              value: windowLabel(r.window)),
          InfoLine(
            icon: IconsaxPlusLinear.location,
            label: 'Where',
            value:
                '${r.area}${r.distanceKm == null ? '' : ' · ${r.distanceKm!.toStringAsFixed(1)} km'}',
          ),
          if (r.landmark != null)
            Padding(
              padding: EdgeInsets.only(left: 28.w),
              child: Text(
                  '${r.landmark}. The exact address comes when you accept.',
                  style: AppText.caption.copyWith(color: c.textTertiary)),
            ),
          SizedBox(height: 12.w),
          ClipRRect(
            borderRadius: BorderRadius.circular(18.w),
            child: SizedBox(
              height: 140.w,
              child: RijMap(
                lat: centre.lat,
                lng: centre.lng,
                kmAcross: 4,
                labels: [MapLabel(r.area, centre.lat, centre.lng)],
              ),
            ),
          ),
          SizedBox(height: 16.w),
          InfoLine(label: 'Client pays', value: Naira.format(r.price)),
          InfoLine(
              label: 'You receive', value: Naira.format(r.price), strong: true),
          Text(
            'The client pays Employi when you accept. You get it as soon as they confirm the job is done.',
            style: AppText.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

// A reason was asked for on every decline but never sent anywhere, so it
// went (2026-10-23: never collect what isn't used). Kept for if it's
// ever sent to the API, which accepts one.
//
// Future<String?> _declineReason(BuildContext context) =>
//     showModalBottomSheet<String>(
//       context: context,
//       useRootNavigator: true,
//       showDragHandle: true,
//       backgroundColor: context.colors.surface,
//       builder: (context) => SafeArea(
//         child: Padding(
//           padding: EdgeInsets.fromLTRB(
//               AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               Text('Why are you declining?', style: AppText.headline),
//               SizedBox(height: 6.w),
//               Text(
//                   'It helps us send you better requests. The client won\'t see it.',
//                   style: AppText.body
//                       .copyWith(color: context.colors.textSecondary)),
//               SizedBox(height: 14.w),
//               Wrap(
//                 spacing: 8.w,
//                 children: [
//                   for (final r in const [
//                     "I'm busy then",
//                     'Too far',
//                     'Price too low',
//                     "Not my kind of job"
//                   ])
//                     PromptChip(
//                         label: r, onTap: () => Navigator.of(context).pop(r)),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );

// ---------------------------------------------------------------- job board

/// The artisan's Jobs tab: open jobs near them (a list or a map), and the
/// quotes they've sent.
class JobsBoard extends StatefulWidget {
  const JobsBoard({super.key, this.startOnMap = false});

  final bool startOnMap;

  @override
  State<JobsBoard> createState() => _JobsBoardState();
}

class _JobsBoardState extends State<JobsBoard> {
  int _tab = 0;
  String? _trade;
  bool _mine = true;
  late bool _map = widget.startOnMap;
  JobPost? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.watch<SessionController>();
    final trades = session.tradeIds;
    final area = session.area;
    final g = AppSpace.gutter;
    final categoryIds = _trade != null
        ? {_trade!}
        : (_mine && trades.isNotEmpty ? trades.toSet() : null);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabTitle(
              'Jobs',
              trailing: _tab == 0
                  ? Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AreaPill(),
                          SizedBox(width: 6.w),
                          AppIconButton(
                            icon: _map
                                ? IconsaxPlusLinear.menu_1
                                : IconsaxPlusLinear.map,
                            filled: true,
                            semanticLabel:
                                _map ? 'Show as a list' : 'Show on a map',
                            onPressed: () => setState(() => _map = !_map),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            if (session.isSignedIn)
              Padding(
                padding: EdgeInsets.fromLTRB(g, 0, g, 4.w),
                child: SegmentedTabs(
                  labels: const ['Near you', 'Your quotes'],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
            if (_tab == 0) ...[
              ChipRow(children: [
                if (trades.isNotEmpty)
                  PromptChip(
                    label: 'My trades',
                    icon: IconsaxPlusLinear.briefcase,
                    solid: _mine && _trade == null,
                    onTap: () => setState(() {
                      _mine = true;
                      _trade = null;
                    }),
                  ),
                PromptChip(
                  label: 'All',
                  solid: !_mine && _trade == null ||
                      (trades.isEmpty && _trade == null),
                  onTap: () => setState(() {
                    _mine = false;
                    _trade = null;
                  }),
                ),
                for (final t in Trades.all)
                  PromptChip(
                    label: t.name,
                    icon: CategoryIcons.of(t.iconKey),
                    solid: _trade == t.id,
                    onTap: () => setState(() => _trade = t.id),
                  ),
              ]),
              Expanded(
                child: Loader<(List<JobPost>, JobDemand)>(
                  key: ValueKey('$area/${categoryIds?.join(',')}'),
                  load: () async {
                    final jobs = context.read<JobRepository>();
                    final r = await Future.wait<Object>([
                      jobs.openJobsNearby(
                          area: area ?? AreaPill.city,
                          categoryIds: categoryIds,
                          limit: 30),
                      jobs.demand(
                          area: area,
                          categoryId: categoryIds?.length == 1
                              ? categoryIds!.first
                              : null),
                    ]);
                    return (r[0] as List<JobPost>, r[1] as JobDemand);
                  },
                  builder: (context, data, reload) {
                    final (list, demand) = data;
                    final header = Padding(
                      padding: EdgeInsets.fromLTRB(g, 2.w, g, 2.w),
                      child: Text(
                        '${demand.openThisWeek} open this week${demand.typicalBudgetMin == null ? '' : ' · most pay ${Naira.range(demand.typicalBudgetMin, demand.typicalBudgetMax)}'}',
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary),
                      ),
                    );
                    if (_map) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          Expanded(
                              child: _JobsMapView(
                                  jobs: list,
                                  area: area,
                                  selected: _selected,
                                  onSelect: (j) =>
                                      setState(() => _selected = j))),
                        ],
                      );
                    }
                    return RefreshIndicator(
                      color: c.brandStroke,
                      onRefresh: reload,
                      child: ListView(
                        padding: EdgeInsets.only(bottom: 24.w),
                        children: [
                          header,
                          if (list.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 60.w),
                              child: const EmptyState(
                                icon: IconsaxPlusLinear.briefcase,
                                title: 'No open jobs here yet',
                                message:
                                    'Try all trades, or another area. New jobs come in through the day.',
                              ),
                            ),
                          for (final (i, j) in list.indexed)
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: g),
                              child: JobTile(
                                job: j,
                                hasArea: area != null,
                                divider: i < list.length - 1,
                                onTap: () => context.push(Routes.job(j.id)),
                              ),
                            ),
                          if (session.isGuest) ...[
                            SizedBox(height: 12.w),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: g),
                              child: Container(
                                padding:
                                    EdgeInsets.fromLTRB(16.w, 12.w, 12.w, 12.w),
                                decoration: BoxDecoration(
                                    color: c.surfaceStrong,
                                    borderRadius: BorderRadius.circular(18.w)),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Ready to quote?',
                                              style: AppText.titleSmall
                                                  .copyWith(
                                                      color:
                                                          c.onSurfaceStrong)),
                                          Text('Free. Just your phone number.',
                                              style: AppText.bodySmall.copyWith(
                                                  color: c.onSurfaceStrong
                                                      .withValues(
                                                          alpha: 0.65))),
                                        ],
                                      ),
                                    ),
                                    AppButton(
                                      label: 'Join free',
                                      size: AppButtonSize.small,
                                      expand: false,
                                      onPressed: () => context
                                          .read<AuthGate>()
                                          .ensureSignedIn(context,
                                              AuthPrompt.joinAsArtisan),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else
              const Expanded(child: QuotesList()),
          ],
        ),
      ),
    );
  }
}

class _JobsMapView extends StatelessWidget {
  const _JobsMapView(
      {required this.jobs,
      required this.area,
      required this.selected,
      required this.onSelect});

  final List<JobPost> jobs;
  final String? area;
  final JobPost? selected;
  final ValueChanged<JobPost?> onSelect;

  @override
  Widget build(BuildContext context) {
    final centre = AbujaPlaces.centreOf(area);
    final shown = (area == null ? jobs : jobs.where((j) => j.distanceKm <= 5))
        .take(16)
        .toList();
    return Stack(
      children: [
        Positioned.fill(
          child: RijMap(
            lat: centre.lat,
            lng: centre.lng,
            kmAcross: area == null ? 14 : 7,
            fit: area == null,
            showMe: area != null,
            semanticLabel: 'Map of ${shown.length} jobs',
            markers: [
              for (final j in shown)
                if (j.location != null)
                  MapMarker(
                    key: ValueKey(j.id),
                    lat: j.location!.lat,
                    lng: j.location!.lng,
                    child: Semantics(
                      button: true,
                      label: '${j.title}, ${pinPrice(j)}',
                      child: GestureDetector(
                        onTap: () => onSelect(j),
                        child: PricePin(pinPrice(j),
                            urgent: j.isUrgent, selected: selected?.id == j.id),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (selected != null)
          Positioned(
            left: AppSpace.gutter,
            right: AppSpace.gutter,
            bottom: 16.w,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20.w),
                boxShadow: AppShadows.floating,
              ),
              child: JobTile(
                  job: selected!,
                  hasArea: area != null,
                  divider: false,
                  onTap: () => context.push(Routes.job(selected!.id))),
            ),
          ),
      ],
    );
  }
}

/// The quotes the artisan has sent, newest first.
class QuotesList extends StatelessWidget {
  const QuotesList({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Loader<List<Quote>>(
      reloadOn: context.read<LiveUpdates>(),
      load: () => context.read<QuoteRepository>().mine(),
      builder: (context, quotes, reload) => RefreshIndicator(
        color: c.brandStroke,
        onRefresh: reload,
        child: quotes.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: 80.w),
                  const EmptyState(
                    icon: IconsaxPlusLinear.receipt_2,
                    title: 'No quotes sent yet',
                    message:
                        'Quote on jobs near you. Fast, clear quotes win more work.',
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                children: [
                  for (final q in quotes)
                    Pressable(
                      onTap: () => context.push(Routes.job(q.jobId)),
                      pressedScale: 0.99,
                      focusOffset: 0,
                      semanticLabel:
                          '${q.jobTitle ?? 'Job'}, your quote ${Naira.format(q.price)}, ${q.status.name}',
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 14.w),
                        decoration: BoxDecoration(
                            border:
                                Border(bottom: BorderSide(color: c.border))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(q.jobTitle ?? 'Job',
                                      style: AppText.titleSmall),
                                  SizedBox(height: 2.w),
                                  Text('Sent ${RelativeTime.short(q.sentAt)}',
                                      style: AppText.caption
                                          .copyWith(color: c.textTertiary)),
                                  SizedBox(height: 6.w),
                                  StatusTag(
                                    label: switch (q.status) {
                                      QuoteStatus.pending =>
                                        'Waiting for the client',
                                      QuoteStatus.accepted => 'Accepted',
                                      QuoteStatus.declined => 'Not chosen',
                                      QuoteStatus.withdrawn => 'Withdrawn',
                                    },
                                    tone: switch (q.status) {
                                      QuoteStatus.pending => TagTone.warning,
                                      QuoteStatus.accepted => TagTone.success,
                                      _ => TagTone.neutral,
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Text(
                                q.priceMax == null
                                    ? Naira.format(q.price)
                                    : Naira.range(q.price, q.priceMax),
                                style: AppText.titleSmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class MyQuotesScreen extends StatelessWidget {
  const MyQuotesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PageScaffold(title: 'Quotes you sent', body: QuotesList());
}

// ---------------------------------------------------------------- job

/// A job from the board (or a client's price request), with the way to
/// quote on it.
class ArtisanJobScreen extends StatelessWidget {
  const ArtisanJobScreen(
      {super.key, required this.jobId, this.priceRequest = false});

  final String jobId;

  /// A client asked this artisan by name.
  final bool priceRequest;

  @override
  Widget build(BuildContext context) {
    return Loader<(JobPost, Quote?)>(
      reloadOn: context.read<LiveUpdates>(),
      load: () async {
        final quotes = context.read<QuoteRepository>();
        final JobPost job;
        if (priceRequest) {
          final requests = await quotes.quoteRequests();
          final r = requests.firstWhere((j) => j.id == jobId,
              orElse: () =>
                  throw const AppException('That request has been answered.'));
          job = JobPost(
            id: r.id,
            title: r.title,
            categoryId: r.categoryId,
            area: r.area,
            distanceKm: 0,
            postedAt: r.postedAt,
            description: r.description,
            budgetMin: r.budgetMin,
            budgetMax: r.budgetMax,
            isUrgent: r.isUrgent,
            photos: r.photos,
            clientPhoneVerified: true,
            clientJobsPosted: 2,
          );
        } else {
          job = await quotes.job(jobId);
        }
        return (job, await quotes.myQuoteOn(jobId));
      },
      loading: const Scaffold(body: ListSkeleton()),
      builder: (context, data, reload) => _JobView(
          job: data.$1,
          mine: data.$2,
          priceRequest: priceRequest,
          reload: reload),
    );
  }
}

class _JobView extends StatelessWidget {
  const _JobView(
      {required this.job,
      required this.mine,
      required this.priceRequest,
      required this.reload});

  final JobPost job;
  final Quote? mine;
  final bool priceRequest;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final centre = job.location ?? AbujaPlaces.centreOf(job.area);
    return PageScaffold(
      title: job.title,
      subtitle:
          '${categoryName(job.categoryId)} · posted ${RelativeTime.short(job.postedAt)}',
      bottom: mine != null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'You quoted ${mine!.priceMax == null ? Naira.format(mine!.price) : Naira.range(mine!.price, mine!.priceMax)}',
                    style: AppText.titleSmall,
                  ),
                ),
                if (mine!.status == QuoteStatus.pending)
                  AppButton(
                    label: 'Withdraw',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: () async {
                      await context.read<QuoteRepository>().withdraw(mine!.id);
                      await reload();
                    },
                  ),
              ],
            )
          : AppButton(
              label: priceRequest ? 'Send your price' : 'Send a quote',
              onPressed: () async {
                final ok = await context
                    .read<AuthGate>()
                    .ensureSignedIn(context, AuthPrompt.sendQuote);
                if (!ok || !context.mounted) return;
                if (!await ensureVerified(context) || !context.mounted) return;
                final sent = await context.push<bool>(Routes.sendQuote(job.id),
                    extra: job);
                if (sent == true) await reload();
              },
            ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
        children: [
          Row(
            children: [
              Text(budgetLabel(job.budgetMin, job.budgetMax),
                  style:
                      AppText.headline.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (job.isUrgent)
                const StatusTag(
                    label: 'Urgent',
                    tone: TagTone.warning,
                    icon: IconsaxPlusBold.flash_1),
            ],
          ),
          SizedBox(height: 4.w),
          Text(
            job.quoteCount == 0
                ? 'No quotes yet. Be the first.'
                : '${job.quoteCount} artisan${job.quoteCount == 1 ? ' has' : 's have'} quoted',
            style: AppText.bodySmall.copyWith(
                color: job.quoteCount == 0 ? c.success : c.textSecondary,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 16.w),
          if (job.description != null) ...[
            Text(job.description!, style: AppText.bodyLarge),
            SizedBox(height: 12.w),
          ],
          if (job.photos.isNotEmpty) ...[
            Wrap(spacing: 8.w, children: [
              for (final p in job.photos) PhotoThumb(image: p, size: 88)
            ]),
            SizedBox(height: 12.w),
          ],
          InfoLine(
            icon: IconsaxPlusLinear.location,
            label: 'Where',
            value: job.distanceKm == 0
                ? job.area
                : '${job.area} · ${job.distanceKm.toStringAsFixed(1)} km',
          ),
          InfoLine(
            icon: IconsaxPlusLinear.user_tick,
            label: 'Client',
            value:
                '${job.clientPhoneVerified ? 'Phone verified' : 'New'} · ${job.clientJobsPosted} job${job.clientJobsPosted == 1 ? '' : 's'} posted',
          ),
          SizedBox(height: 12.w),
          ClipRRect(
            borderRadius: BorderRadius.circular(18.w),
            child: SizedBox(
              height: 150.w,
              child: RijMap(
                lat: centre.lat,
                lng: centre.lng,
                kmAcross: 4,
                markers: [
                  MapMarker(
                      lat: centre.lat,
                      lng: centre.lng,
                      child: PricePin(
                          budgetLabel(job.budgetMin, job.budgetMax)
                              .replaceAll(',000', 'k'),
                          urgent: job.isUrgent,
                          selected: true)),
                ],
              ),
            ),
          ),
          SizedBox(height: 8.w),
          Text('The exact address goes to the artisan the client books.',
              style: AppText.caption.copyWith(color: c.textTertiary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- quote

/// Sending a quote: a price (or a range), when you can come, and a word to
/// the client.
class SendQuoteScreen extends StatefulWidget {
  const SendQuoteScreen({super.key, required this.jobId, this.job});

  final String jobId;
  final JobPost? job;

  @override
  State<SendQuoteScreen> createState() => _SendQuoteScreenState();
}

class _SendQuoteScreenState extends State<SendQuoteScreen> {
  int _type = 0;
  final _price = TextEditingController();
  final _max = TextEditingController();
  final _note = TextEditingController();
  TimeWindow? _when;
  String? _whenLabel;
  bool _sending = false;
  bool _tried = false;
  late JobPost? _job = widget.job;

  static const _templates = [
    'I can come today',
    'Price includes labour only',
    "I'll check before I start",
    'I bring my own tools'
  ];

  @override
  void initState() {
    super.initState();
    // Opened from a link or a notice rather than the job: fetch it, so the
    // title and budget still show.
    if (_job == null) {
      context.read<QuoteRepository>().job(widget.jobId).then((j) {
        if (mounted) setState(() => _job = j);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_price, _max, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _n(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));

  String? get _error {
    final p = _n(_price);
    if (p == null || p < 500) return 'Enter your price.';
    if (_type == 1) {
      final m = _n(_max);
      if (m == null || m <= p) {
        return 'The top of the range must be more than the bottom.';
      }
    }
    return null;
  }

  Future<void> _send() async {
    setState(() => _tried = true);
    if (_error != null) return;
    setState(() => _sending = true);
    final repo = context.read<QuoteRepository>();
    final sent = await runAction(
      context,
      () => repo.send(
        widget.jobId,
        QuoteDraft(
          price: _n(_price)!,
          priceMax: _type == 1 ? _n(_max) : null,
          message: _note.text.trim().isEmpty ? null : _note.text.trim(),
          canStartAt: _when?.start,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent == null) return;
    await _offerPings();
    if (!mounted) return;
    showToast(context, 'Quote sent. We\'ll tell you if the client picks you.');
    goBack(context, true);
  }

  /// After a first quote, the one time notifications are offered: it's when
  /// hearing back plainly matters.
  Future<void> _offerPings() async {
    final session = context.read<SessionController>();
    final push = context.read<PushPermission>();
    if (session.pushAsked || await push.granted()) return;
    await session.markPushAsked();
    if (!mounted) return;
    final yes = await confirmSheet(
      context,
      title: 'Know when the client picks you?',
      message: "Turn on notifications and we'll tell you the moment a client "
          'accepts, and when new jobs come in near you.',
      confirm: 'Turn on notifications',
      cancel: 'Not now',
    );
    if (yes) await push.request();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = _job;
    final price = _n(_price);
    final label = price == null
        ? 'Send quote'
        : 'Send quote · ${_type == 1 && _n(_max) != null ? Naira.range(price, _n(_max)) : Naira.format(price)}';
    return PageScaffold(
      title: 'Your quote',
      subtitle: job?.title,
      bottom: AppButton(
          label: label,
          isLoading: _sending,
          onPressed: _sending ? null : _send),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
        children: [
          if (job != null && (job.budgetMin != null || job.budgetMax != null))
            InlineNote(
              icon: IconsaxPlusLinear.money_2,
              title:
                  'Client\'s budget: ${budgetLabel(job.budgetMin, job.budgetMax)}',
              message:
                  'Quotes near the budget, with a clear note, get picked most.',
            ),
          SizedBox(height: 16.w),
          SegmentedTabs(
              labels: const ['Fixed price', 'Price range'],
              selected: _type,
              onChanged: (i) => setState(() => _type = i)),
          SizedBox(height: 14.w),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _price,
                  label: _type == 0 ? 'Your price' : 'From',
                  hint: '₦8,000',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  errorText:
                      _tried && _error != null && _error!.startsWith('Enter')
                          ? _error
                          : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_type == 1) ...[
                SizedBox(width: 10.w),
                Expanded(
                  child: AppTextField(
                    controller: _max,
                    label: 'To',
                    hint: '₦12,000',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    errorText: _tried &&
                            _error != null &&
                            _error!.startsWith('The top')
                        ? _error
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
          if (_type == 1)
            Padding(
              padding: EdgeInsets.only(top: 6.w),
              child: Text(
                  'The client picks a price in your range when they book.',
                  style: AppText.caption.copyWith(color: c.textTertiary)),
            ),
          SizedBox(height: 20.w),
          Text('When can you come?', style: AppText.labelSmall),
          SizedBox(height: 6.w),
          Wrap(
            spacing: 8.w,
            children: [
              for (final (l, w) in suggestedWindows(DateTime.now()))
                PromptChip(
                    label: l,
                    selected: _when?.start == w.start,
                    onTap: () => setState(() {
                          _when = w;
                          _whenLabel = l;
                        })),
              PromptChip(
                label: _whenLabel != null &&
                        !suggestedWindows(DateTime.now())
                            .any((x) => x.$1 == _whenLabel)
                    ? _whenLabel!
                    : 'Pick a day',
                icon: IconsaxPlusLinear.calendar_1,
                onTap: () async {
                  final w = await showDayPicker(context);
                  if (w != null) {
                    setState(() {
                      _when = w;
                      _whenLabel = windowLabel(w);
                    });
                  }
                },
              ),
            ],
          ),
          SizedBox(height: 20.w),
          AppTextField(
            controller: _note,
            label: 'A word to the client',
            optional: true,
            hint: 'What the price covers, and how you work',
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 6,
          ),
          SizedBox(height: 4.w),
          Wrap(
            spacing: 8.w,
            children: [
              for (final t in _templates)
                PromptChip(
                  label: t,
                  icon: IconsaxPlusLinear.add,
                  onTap: () => setState(() {
                    _note.text = _note.text.trim().isEmpty
                        ? '$t.'
                        : '${_note.text.trim()} $t.';
                  }),
                ),
            ],
          ),
          SizedBox(height: 16.w),
          Text(
            'The client sees your price, your rating, jobs done and this note. Quoting is free.',
            style: AppText.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}
