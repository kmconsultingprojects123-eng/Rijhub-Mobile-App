import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/live_updates.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// The third tab: Bookings for clients, Schedule for artisans.
class BookingsTab extends StatelessWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: session.role == UserRole.artisan
            ? (session.isGuest ? const _GuestSchedule() : const ScheduleView())
            : (session.isGuest
                ? const _GuestBookings()
                : const _ClientBookings()),
      ),
    );
  }
}

/// A tab's big title.
class TabTitle extends StatelessWidget {
  const TabTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.gutter, 12.w, AppSpace.s8, 8.w),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title,
                    style: AppText.display.copyWith(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8)),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class _GuestBookings extends StatelessWidget {
  const _GuestBookings();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabTitle('Bookings'),
          Expanded(
            child: Center(
              child: EmptyState(
                icon: IconsaxPlusLinear.calendar_tick,
                title: 'Your bookings live here',
                message:
                    'Book an artisan and follow it here: when they are on the way, your start code, and payment.',
                action: AppButton(
                  label: 'Sign in',
                  expand: false,
                  onPressed: () => context
                      .read<AuthGate>()
                      .ensureSignedIn(context, AuthPrompt.bookings),
                ),
              ),
            ),
          ),
        ],
      );
}

class _ClientBookings extends StatefulWidget {
  const _ClientBookings();

  @override
  State<_ClientBookings> createState() => _ClientBookingsState();
}

class _ClientBookingsState extends State<_ClientBookings> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabTitle(
          'Bookings',
          trailing: AppButton(
            label: 'Post a job',
            size: AppButtonSize.small,
            variant: AppButtonVariant.tertiary,
            leading: const Icon(IconsaxPlusLinear.add),
            expand: false,
            onPressed: () => context.push(Routes.postJob),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: SegmentedTabs(
            labels: const ['Upcoming', 'Past'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        SizedBox(height: 4.w),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              // Everything still to happen in one list: jobs waiting on
              // quotes first (they need you), then booked work.
              Loader<(List<ClientJob>, List<Booking>)>(
                reloadOn: Listenable.merge([session, context.read<LiveUpdates>()]),
                load: () async {
                  final r = await Future.wait<Object>([
                    context.read<ClientJobRepository>().mine(),
                    context
                        .read<BookingRepository>()
                        .upcoming(as: UserRole.client),
                  ]);
                  final jobs = (r[0] as List<ClientJob>)
                      .where((j) => j.status == JobStatus.open)
                      .toList();
                  return (jobs, r[1] as List<Booking>);
                },
                builder: (context, data, reload) {
                  final (jobs, bookings) = data;
                  Widget label(String text) => Padding(
                        padding: EdgeInsets.only(top: 14.w, bottom: 2.w),
                        child: Text(text,
                            style: AppText.labelSmall
                                .copyWith(color: context.colors.textSecondary)),
                      );
                  return RefreshIndicator(
                    color: context.colors.brandStroke,
                    onRefresh: reload,
                    child: jobs.isEmpty && bookings.isEmpty
                        ? _Empty(
                            icon: IconsaxPlusLinear.calendar_tick,
                            title: 'Nothing coming up',
                            message:
                                'Tell Employi what needs fixing, and book a trusted artisan in minutes.',
                            action: 'Ask Employi',
                            onAction: () => context.push(Routes.ask),
                          )
                        : ListView(
                            padding: EdgeInsets.symmetric(
                                horizontal: AppSpace.gutter),
                            children: [
                              if (jobs.isNotEmpty) ...[
                                if (bookings.isNotEmpty) label('Your jobs'),
                                for (final (i, j) in jobs.indexed)
                                  ClientJobRow(
                                    job: j,
                                    divider: i < jobs.length - 1,
                                    onTap: () async {
                                      await context
                                          .push(Routes.clientJob(j.id));
                                      await reload();
                                    },
                                  ),
                              ],
                              if (bookings.isNotEmpty) ...[
                                if (jobs.isNotEmpty) label('Booked'),
                                for (final (i, b) in bookings.indexed)
                                  BookingTile(
                                    booking: b,
                                    artisan: false,
                                    divider: i < bookings.length - 1,
                                    onTap: () async {
                                      await context.push(Routes.booking(b.id));
                                      await reload();
                                    },
                                  ),
                              ],
                            ],
                          ),
                  );
                },
              ),
              Loader<List<Booking>>(
                reloadOn: Listenable.merge([session, context.read<LiveUpdates>()]),
                load: () => context
                    .read<BookingFlowRepository>()
                    .past(as: UserRole.client),
                builder: (context, list, reload) => RefreshIndicator(
                  color: context.colors.brandStroke,
                  onRefresh: reload,
                  child: list.isEmpty
                      ? const _Empty(
                          icon: IconsaxPlusLinear.clock,
                          title: 'Nothing here yet',
                          message:
                              'Finished and cancelled bookings show here, with your receipts.',
                        )
                      : ListView(
                          padding:
                              EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                          children: [
                            for (final (i, b) in list.indexed)
                              BookingTile(
                                booking: b,
                                artisan: false,
                                divider: i < list.length - 1,
                                onTap: () async {
                                  await context.push(Routes.booking(b.id));
                                  await reload();
                                },
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(
      {required this.icon,
      required this.title,
      required this.message,
      this.action,
      this.onAction});

  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          SizedBox(height: 90.w),
          EmptyState(
            icon: icon,
            title: title,
            message: message,
            action: action == null
                ? null
                : AppButton(label: action!, expand: false, onPressed: onAction),
          ),
        ],
      );
}

/// A client's posted job as a row: what, when, and how the quotes stand.
class ClientJobRow extends StatelessWidget {
  const ClientJobRow(
      {super.key, required this.job, required this.onTap, this.divider = true});

  final ClientJob job;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = job.pendingQuotes;
    final (label, tone) = switch (job.status) {
      JobStatus.booked => ('Booked', TagTone.success),
      JobStatus.closed => ('Closed', TagTone.neutral),
      JobStatus.open when n > 0 => (
          '$n quote${n == 1 ? '' : 's'} to compare',
          TagTone.brand
        ),
      JobStatus.open => ('Waiting for quotes', TagTone.warning),
    };
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${job.title}, posted ${RelativeTime.spoken(job.postedAt)}, $label',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.w),
        decoration: BoxDecoration(
            border:
                divider ? Border(bottom: BorderSide(color: c.border)) : null),
        child: Row(
          children: [
            job.photos.isNotEmpty
                ? PhotoThumb(image: job.photos.first, size: 52)
                : TradeIcon(categoryId: job.categoryId, size: 52),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleSmall),
                  SizedBox(height: 2.w),
                  Text(
                      '${job.area} · posted ${RelativeTime.short(job.postedAt)}',
                      style:
                          AppText.bodySmall.copyWith(color: c.textSecondary)),
                  SizedBox(height: 6.w),
                  StatusTag(label: label, tone: tone),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 18.w, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- artisan

class _GuestSchedule extends StatelessWidget {
  const _GuestSchedule();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabTitle('Schedule'),
          Expanded(
            child: Center(
              child: EmptyState(
                icon: IconsaxPlusLinear.calendar_tick,
                title: 'Your jobs, day by day',
                message:
                    'Create your free profile and the jobs you accept line up here, with directions and your pay.',
                action: AppButton(
                  label: 'Create your free profile',
                  expand: false,
                  onPressed: () => context
                      .read<AuthGate>()
                      .ensureSignedIn(context, AuthPrompt.joinAsArtisan),
                ),
              ),
            ),
          ),
        ],
      );
}

/// The artisan's schedule: a week strip, the day's jobs on a timeline, and
/// the jobs already done.
class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key});

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  int _tab = 0;
  late DateTime _day = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.read<SessionController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabTitle('Schedule'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: SegmentedTabs(
            labels: const ['Upcoming', 'Done'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? Loader<List<Booking>>(
                  reloadOn: Listenable.merge([session, context.read<LiveUpdates>()]),
                  load: () => context
                      .read<BookingRepository>()
                      .upcoming(as: UserRole.artisan),
                  builder: (context, list, reload) {
                    final today = _dateOnly(DateTime.now());
                    final days = [
                      for (var i = 0; i < 7; i++)
                        DateTime(today.year, today.month, today.day + i)
                    ];
                    final busy = {
                      for (final b in list) _dateOnly(b.scheduledAt)
                    };
                    final ofDay = list
                        .where((b) => _dateOnly(b.scheduledAt) == _day)
                        .toList();
                    final later = list
                        .where(
                            (b) => _dateOnly(b.scheduledAt).isAfter(days.last))
                        .toList();
                    return RefreshIndicator(
                      color: c.brandStroke,
                      onRefresh: reload,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                            AppSpace.gutter, 14.w, AppSpace.gutter, 24.w),
                        children: [
                          DayStrip(
                              days: days,
                              selected: _day,
                              busy: busy,
                              onPick: (d) => setState(() => _day = d)),
                          SizedBox(height: 18.w),
                          Text(
                            '${Schedule.dayLabel(_day)} · ${ofDay.isEmpty ? 'no jobs' : '${ofDay.length} job${ofDay.length == 1 ? '' : 's'}'}',
                            style: AppText.labelSmall
                                .copyWith(color: c.textSecondary),
                          ),
                          SizedBox(height: 8.w),
                          if (ofDay.isEmpty)
                            InlineNote(
                              icon: IconsaxPlusLinear.briefcase,
                              title: 'A free day',
                              message: 'Quote on jobs near you to fill it.',
                            )
                          else
                            for (final (i, b) in ofDay.indexed)
                              TimelineSlot(
                                last: i == ofDay.length - 1,
                                dot: b.status == BookingStatus.requested
                                    ? c.warning
                                    : c.textPrimary,
                                child: ScheduleCard(
                                  booking: b,
                                  onTap: () async {
                                    await context.push(Routes.booking(b.id));
                                    await reload();
                                  },
                                ),
                              ),
                          if (later.isNotEmpty) ...[
                            SizedBox(height: 24.w),
                            const SectionTitle('Later'),
                            for (final (i, b) in later.indexed)
                              BookingTile(
                                booking: b,
                                artisan: true,
                                divider: i < later.length - 1,
                                onTap: () => context.push(Routes.booking(b.id)),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                )
              : Loader<List<Booking>>(
                  reloadOn: Listenable.merge([session, context.read<LiveUpdates>()]),
                  load: () => context
                      .read<BookingFlowRepository>()
                      .past(as: UserRole.artisan),
                  builder: (context, list, reload) => RefreshIndicator(
                    color: c.brandStroke,
                    onRefresh: reload,
                    child: list.isEmpty
                        ? const _Empty(
                            icon: IconsaxPlusLinear.task_square,
                            title: 'No jobs done yet',
                            message:
                                'Finished jobs show here, with what you earned and the stars you got.',
                          )
                        : ListView(
                            padding: EdgeInsets.symmetric(
                                horizontal: AppSpace.gutter),
                            children: [
                              for (final (i, b) in list.indexed)
                                BookingTile(
                                  booking: b,
                                  artisan: true,
                                  divider: i < list.length - 1,
                                  onTap: () =>
                                      context.push(Routes.booking(b.id)),
                                ),
                            ],
                          ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A week of days to pick from, with a dot on days that have jobs.
class DayStrip extends StatelessWidget {
  const DayStrip(
      {super.key,
      required this.days,
      required this.selected,
      required this.onPick,
      this.busy = const {}});

  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final Set<DateTime> busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) SizedBox(width: 6.w),
          Expanded(
            child: Semantics(
              button: true,
              selected: days[i] == selected,
              label:
                  '${Schedule.dayLabel(days[i])}${busy.contains(days[i]) ? ', has jobs' : ''}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onPick(days[i]),
                child: Container(
                  height: 60.w,
                  decoration: BoxDecoration(
                    color: days[i] == selected ? c.surfaceStrong : c.surface,
                    borderRadius: BorderRadius.circular(16.w),
                    border: days[i] == selected
                        ? null
                        : Border.all(color: c.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        names[days[i].weekday - 1],
                        style: AppText.caption.copyWith(
                          color: days[i] == selected
                              ? c.onSurfaceStrong.withValues(alpha: 0.7)
                              : c.textTertiary,
                        ),
                      ),
                      SizedBox(height: 2.w),
                      Text(
                        '${days[i].day}',
                        style: AppText.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: days[i] == selected
                              ? c.onSurfaceStrong
                              : c.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3.w),
                      Container(
                        width: 5.w,
                        height: 5.w,
                        decoration: BoxDecoration(
                          color: busy.contains(days[i])
                              ? (days[i] == selected
                                  ? c.onSurfaceStrong
                                  : c.brandStroke)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A dot on a rail, then the card: one stop in the day.
class TimelineSlot extends StatelessWidget {
  const TimelineSlot(
      {super.key, required this.child, this.dot, this.last = false});

  final Widget child;
  final Color? dot;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16.w,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!last)
                  Positioned(
                      top: 24.w,
                      bottom: 0,
                      child: Container(width: 2, color: c.border)),
                Positioned(
                  top: 18.w,
                  child: Container(
                    width: 12.w,
                    height: 12.w,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: dot ?? c.textPrimary, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
              child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : 12.w),
                  child: child)),
        ],
      ),
    );
  }
}

/// A booking on the artisan's timeline.
class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key, required this.booking, required this.onTap});

  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = booking;
    final (label, tone) = bookingStatus(b, artisan: true);
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '${Schedule.time(b.scheduledAt)}, ${b.serviceName} for ${b.counterpartName}, ${b.area}, $label',
      child: Container(
        padding: EdgeInsets.fromLTRB(14.w, 12.w, 12.w, 12.w),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.w),
            border: Border.all(color: c.border)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Schedule.time(b.scheduledAt),
                      style: AppText.caption.copyWith(
                          color: c.textTertiary, fontWeight: FontWeight.w700)),
                  SizedBox(height: 3.w),
                  Text(b.serviceName, style: AppText.titleSmall),
                  SizedBox(height: 2.w),
                  Text(
                    '${b.counterpartName} · ${b.area}${b.distanceKm == null ? '' : ' · ${b.distanceKm!.toStringAsFixed(1)} km'}',
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                  SizedBox(height: 8.w),
                  Row(
                    children: [
                      StatusTag(label: label, tone: tone),
                      if (b.price != null) ...[
                        SizedBox(width: 8.w),
                        Text(Naira.format(b.price!), style: AppText.labelSmall),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 18.w, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
