import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_flow.dart';
import '../shared/cards.dart';
import '../shared/page.dart';
import '../shared/voice.dart';
import 'booking_sheets.dart';

/// One booking, for the client or the artisan: where it stands, who, when
/// and where, the money, and the next thing to do.
class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final artisan = context
        .select<SessionController, bool>((s) => s.role == UserRole.artisan);
    return Loader<Booking>(
      load: () => context.read<BookingFlowRepository>().byId(bookingId),
      loading: const Scaffold(body: ListSkeleton()),
      builder: (context, booking, reload) => _BookingView(
        booking: booking,
        artisan: artisan,
        reload: reload,
      ),
    );
  }
}

class _BookingView extends StatefulWidget {
  const _BookingView(
      {required this.booking, required this.artisan, required this.reload});

  final Booking booking;
  final bool artisan;
  final Future<void> Function() reload;

  @override
  State<_BookingView> createState() => _BookingViewState();
}

class _BookingViewState extends State<_BookingView> {
  late Booking _b = widget.booking;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _BookingView old) {
    super.didUpdateWidget(old);
    if (old.booking != widget.booking) _b = widget.booking;
  }

  String get _first => _b.counterpartName.split(' ').first;

  Future<void> _do(Future<Booking> Function(BookingFlowRepository r) action,
      {String? done}) async {
    setState(() => _busy = true);
    final repo = context.read<BookingFlowRepository>();
    final result = await runAction(context, () => action(repo));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _b = result;
    });
    if (result != null && done != null) showToast(context, done);
  }

  Future<void> _call() async {
    final phone = _b.counterpartPhone;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _message() async {
    final convo = await context.read<ChatRepository>().forBooking(_b.id);
    if (mounted) context.push(Routes.chat(convo.id));
  }

  Future<void> _directions() async {
    final at = AbujaPlaces.centreOf(_b.area);
    final query = Uri.encodeComponent('${_b.landmark ?? ''} ${_b.area}, Abuja');
    final google =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');
    if (!await launchUrl(google, mode: LaunchMode.externalApplication)) {
      await launchUrl(
          Uri.parse('https://maps.apple.com/?ll=${at.lat},${at.lng}'));
    }
  }

  Future<void> _cancel() async {
    final reason =
        await showCancelSheet(context, booking: _b, artisan: widget.artisan);
    if (reason == null || !mounted) return;
    await _do((r) => r.cancel(_b.id, reason: reason),
        done: widget.artisan
            ? 'Booking cancelled. The client is refunded.'
            : 'Booking cancelled. Your refund is on its way.');
  }

  Future<void> _reschedule() async {
    final window = await showRescheduleSheet(context);
    if (window == null || !mounted) return;
    await _do((r) => r.reschedule(_b.id, window.start),
        done: 'Moved to ${windowLabel(window)}');
  }

  Future<void> _confirmDone() async {
    final ok = await confirmSheet(
      context,
      title: 'Is the job done?',
      message:
          'We\'ll release ${Naira.format(_b.price ?? 0)} to $_first. Only confirm once you\'re happy with the work.',
      confirm: 'Yes, release payment',
      cancel: 'Not yet',
    );
    if (!ok || !mounted) return;
    await _do((r) => r.confirmDone(_b.id));
    if (mounted && _b.yourRating == null) await _review();
  }

  Future<void> _review() async {
    final result = await showReviewSheet(context,
        name: _b.counterpartName,
        photo: _b.counterpartPhoto,
        service: _b.serviceName);
    if (result == null || !mounted) return;
    await _do((r) => r.review(_b.id, rating: result.$1, text: result.$2),
        done: 'Thanks! Your review helps others choose.');
  }

  Future<void> _start() async {
    final code = await showStartCodeSheet(context, clientName: _first);
    if (code == null || !mounted) return;
    await _do((r) => r.start(_b.id, code), done: 'Job started. Good luck!');
  }

  Future<void> _finish() async {
    final ok = await confirmSheet(
      context,
      title: 'Finished the job?',
      message:
          'We\'ll ask $_first to confirm. You get paid as soon as they do.',
      confirm: 'Yes, mark as done',
      cancel: 'Not yet',
    );
    if (!ok || !mounted) return;
    await _do((r) => r.finish(_b.id),
        done: 'Marked as done. We\'ve asked $_first to confirm.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final b = _b;
    final artisan = widget.artisan;
    final showMap = b.status == BookingStatus.onTheWay ||
        (artisan && b.status == BookingStatus.confirmed);
    return PageScaffold(
      title: b.serviceName,
      actions: [
        AppIconButton(
          icon: IconsaxPlusLinear.message_question,
          semanticLabel: 'Get help with this booking',
          onPressed: () => context.push(Routes.support),
        ),
      ],
      bottom: _actions(context),
      body: RefreshIndicator(
        color: c.brandStroke,
        onRefresh: () async {
          final fresh = await context.read<BookingFlowRepository>().byId(b.id);
          if (mounted) setState(() => _b = fresh);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(g, 4.w, g, 24.w),
          children: [
            _Status(booking: b, artisan: artisan),
            if (showMap) ...[
              SizedBox(height: 16.w),
              _LiveMap(booking: b, artisan: artisan, onDirections: _directions),
            ],
            SizedBox(height: 16.w),
            _Person(
              booking: b,
              artisan: artisan,
              onCall: b.isOver ? null : _call,
              onMessage: _message,
              onProfile: !artisan && b.artisanId != null
                  ? () => context.push(Routes.artisan(b.artisanId!))
                  : null,
            ),
            if (!artisan &&
                b.startCode != null &&
                (b.status == BookingStatus.confirmed ||
                    b.status == BookingStatus.onTheWay)) ...[
              SizedBox(height: 12.w),
              _StartCode(code: b.startCode!, name: _first),
            ],
            SizedBox(height: 20.w),
            const SectionTitle('Details'),
            SizedBox(height: 6.w),
            _Detail(IconsaxPlusLinear.calendar_1,
                Schedule.dayAndTime(b.scheduledAt)),
            _Detail(
              IconsaxPlusLinear.location,
              [b.landmark, b.area].whereType<String>().join(', '),
              // The map carries directions when it shows.
              trailing: artisan && !b.isOver && !showMap
                  ? AppButton(
                      label: 'Directions',
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.secondary,
                      expand: false,
                      onPressed: _directions,
                    )
                  : null,
            ),
            if (b.notes != null)
              _Detail(IconsaxPlusLinear.message_text_1, b.notes!),
            if (b.voiceNote != null) ...[
              SizedBox(height: 6.w),
              PlayableVoiceNote(note: b.voiceNote!),
            ],
            if (b.photos.isNotEmpty) ...[
              SizedBox(height: 8.w),
              Wrap(
                spacing: 8.w,
                children: [
                  for (final p in b.photos) PhotoThumb(image: p, size: 72)
                ],
              ),
            ],
            SizedBox(height: 20.w),
            SectionTitle(artisan ? 'Your pay' : 'Payment'),
            SizedBox(height: 6.w),
            _Money(booking: b, artisan: artisan),
            if (!b.isOver && b.status != BookingStatus.inProgress) ...[
              SizedBox(height: 20.w),
              Row(
                children: [
                  if (!artisan && b.status != BookingStatus.requested)
                    Expanded(
                      child: AppButton(
                        label: 'Reschedule',
                        variant: AppButtonVariant.secondary,
                        onPressed: _busy ? null : _reschedule,
                      ),
                    ),
                  if (!artisan && b.status != BookingStatus.requested)
                    SizedBox(width: 10.w),
                  Expanded(
                    child: AppButton(
                      label: artisan
                          ? "Can't make it"
                          : (b.status == BookingStatus.requested
                              ? 'Cancel request'
                              : 'Cancel'),
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : _cancel,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The next thing to do, pinned at the bottom: one primary action.
  Widget? _actions(BuildContext context) {
    final b = _b;
    if (widget.artisan) {
      return switch (b.status) {
        BookingStatus.confirmed => AppButton(
            label: "I'm on my way",
            leading: const Icon(IconsaxPlusLinear.routing_2),
            isLoading: _busy,
            onPressed: _busy
                ? null
                : () => _do((r) => r.onMyWay(b.id),
                    done: 'We\'ve told $_first you\'re on your way.'),
          ),
        BookingStatus.onTheWay => AppButton(
            label: 'Start the job',
            leading: const Icon(IconsaxPlusLinear.key),
            isLoading: _busy,
            onPressed: _busy ? null : _start,
          ),
        BookingStatus.inProgress => AppButton(
            label: 'Mark as done',
            isLoading: _busy,
            onPressed: _busy ? null : _finish),
        BookingStatus.completed when b.payment == PaymentState.held =>
          const _Waiting(
              text:
                  'Waiting for the client to confirm. You get paid as soon as they do.'),
        _ => null,
      };
    }
    return switch (b.status) {
      BookingStatus.completed when b.payment == PaymentState.held => AppButton(
          label: "Confirm it's done",
          isLoading: _busy,
          onPressed: _busy ? null : _confirmDone),
      BookingStatus.completed when b.yourRating == null =>
        AppButton(label: 'Rate $_first', onPressed: _review),
      BookingStatus.completed ||
      BookingStatus.cancelled when b.artisanId != null =>
        AppButton(
            label: 'Book $_first again',
            onPressed: () => context.push(Routes.artisan(b.artisanId!))),
      BookingStatus.inProgress => AppButton(
          label: 'Message $_first',
          variant: AppButtonVariant.secondary,
          onPressed: _message),
      _ => null,
    };
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(IconsaxPlusLinear.clock, size: 20.w, color: c.textSecondary),
        SizedBox(width: 10.w),
        Expanded(
            child: Text(text,
                style: AppText.bodySmall.copyWith(color: c.textSecondary))),
      ],
    );
  }
}

/// Requested · Confirmed · On the way · Working · Done.
/// Where the booking stands, said plainly, over a slim five-step bar.
class _Status extends StatelessWidget {
  const _Status({required this.booking, required this.artisan});

  final Booking booking;
  final bool artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = booking;
    final first = b.counterpartName.split(' ').first;
    final when = Schedule.inSentence(b.scheduledAt);
    final (title, line) = switch (b.status) {
      BookingStatus.requested => artisan
          ? ('New request', 'Answer soon, or it goes to someone else.')
          : ('Waiting for $first', 'Most artisans answer within 15 minutes.'),
      BookingStatus.confirmed => artisan
          ? ('Confirmed', "You're due in ${b.area} $when.")
          : ('Confirmed', '$first comes $when.'),
      BookingStatus.onTheWay => artisan
          ? ('On your way', '$first knows you\'re coming.')
          : (
              '$first is on the way',
              'About ${b.etaMinutes ?? 15} minutes away.'
            ),
      BookingStatus.inProgress => artisan
          ? ('Working', 'Mark it done when you finish.')
          : (
              'Work in progress',
              "Tell us when it's done, and we'll pay $first."
            ),
      BookingStatus.completed when b.payment == PaymentState.held => artisan
          ? ('Waiting for $first', 'You get paid as soon as they confirm.')
          : ("Is it done?", 'Confirm, and we release your payment to $first.'),
      BookingStatus.completed => (
          'Done',
          artisan ? 'Paid. Nice work.' : 'Thanks for booking through RijHub.'
        ),
      BookingStatus.cancelled => (
          'Cancelled',
          b.cancelReason ?? 'This booking was cancelled.'
        ),
    };
    final step = switch (b.status) {
      BookingStatus.requested => 1,
      BookingStatus.confirmed => 2,
      BookingStatus.onTheWay => 3,
      BookingStatus.inProgress => 4,
      BookingStatus.completed => 5,
      BookingStatus.cancelled => 0,
    };
    return Semantics(
      container: true,
      label: b.status == BookingStatus.cancelled ? null : 'Step $step of 5',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.headline),
          SizedBox(height: 2.w),
          Text(line, style: AppText.body.copyWith(color: c.textSecondary)),
          if (step > 0) ...[
            SizedBox(height: 12.w),
            Row(
              children: [
                for (var i = 1; i <= 5; i++) ...[
                  if (i > 1) SizedBox(width: 4.w),
                  Expanded(
                    child: Container(
                      height: 4.w,
                      decoration: BoxDecoration(
                        color: i <= step ? c.brandStroke : c.surfaceMuted,
                        borderRadius: AppRadius.pillAll,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap(
      {required this.booking,
      required this.artisan,
      required this.onDirections});

  final Booking booking;
  final bool artisan;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    // Where the job is, and where the artisan is coming from. You are the
    // blue dot either way; the other person is their photo.
    final place = AbujaPlaces.centreOf(booking.area);
    final from = place.offset(1.4, 1.1);
    final me = artisan ? from : place;
    final them = artisan ? place : from;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18.w),
      child: SizedBox(
        height: 170.w,
        child: Stack(
          children: [
            Positioned.fill(
              child: RijMap(
                lat: (place.lat + from.lat) / 2,
                lng: (place.lng + from.lng) / 2,
                kmAcross: 4.5,
                fit: true,
                semanticLabel: artisan
                    ? 'Map from you to ${booking.counterpartName} in ${booking.area}'
                    : '${booking.counterpartName} on the way to you',
                route: [(from.lat, from.lng), (place.lat, place.lng)],
                markers: [
                  MapMarker(
                      lat: me.lat,
                      lng: me.lng,
                      anchor: Alignment.center,
                      child: const MeDot()),
                  MapMarker(
                    lat: them.lat,
                    lng: them.lng,
                    child: FacePin(
                      name: booking.counterpartName,
                      photo: booking.counterpartPhoto,
                      size: 34,
                      selected: true,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10.w,
              bottom: 10.w,
              child: MapPill(
                  label: 'Directions',
                  icon: IconsaxPlusLinear.routing_2,
                  onTap: onDirections),
            ),
          ],
        ),
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({
    required this.booking,
    required this.artisan,
    required this.onCall,
    required this.onMessage,
    this.onProfile,
  });

  final Booking booking;
  final bool artisan;
  final VoidCallback? onCall;
  final VoidCallback onMessage;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.w),
          border: Border.all(color: c.border)),
      child: Row(
        children: [
          AppAvatar(
              name: booking.counterpartName,
              image: imageFor(booking.counterpartPhoto),
              size: 48.w),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.counterpartName,
                    style: AppText.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                Text(
                  artisan
                      ? 'Client · ${booking.area}${booking.distanceKm == null ? '' : ' · ${booking.distanceKm!.toStringAsFixed(1)} km'}'
                      : 'Your artisan${onProfile == null ? '' : ' · see profile'}',
                  style: AppText.bodySmall.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (onCall != null)
            AppIconButton(
                icon: IconsaxPlusLinear.call,
                filled: true,
                semanticLabel: 'Call',
                onPressed: onCall),
          AppIconButton(
              icon: IconsaxPlusLinear.message,
              filled: true,
              semanticLabel: 'Message',
              onPressed: onMessage),
        ],
      ),
    );
    if (onProfile == null) return card;
    return Pressable(
        onTap: onProfile,
        semanticLabel: '${booking.counterpartName}. Open profile',
        child: card);
  }
}

class _StartCode extends StatelessWidget {
  const _StartCode({required this.code, required this.name});

  final String code;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label:
          'Start code ${code.split('').join(' ')}. Give it to $name when they arrive.',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
            color: c.surfaceStrong, borderRadius: BorderRadius.circular(18.w)),
        child: Row(
          children: [
            Icon(IconsaxPlusLinear.key, size: 22.w, color: c.onSurfaceStrong),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start code',
                      style: AppText.bodySmall.copyWith(
                          color: c.onSurfaceStrong.withValues(alpha: 0.7))),
                  Text('Give it to $name when they arrive',
                      style: AppText.caption.copyWith(
                          color: c.onSurfaceStrong.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Text(code,
                style: AppText.display.copyWith(
                    color: c.onSurfaceStrong,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text, {this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.w),
      child: Row(
        children: [
          Icon(icon, size: 20.w, color: c.textSecondary),
          SizedBox(width: 12.w),
          Expanded(child: Text(text, style: AppText.body)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.booking, required this.artisan});

  final Booking booking;
  final bool artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = booking;
    final price = b.price ?? 0;
    final (icon, color, note) = switch (b.payment) {
      PaymentState.held => (
          IconsaxPlusBold.shield_tick,
          c.success,
          artisan
              ? 'The client has paid. You get it as soon as they confirm the job is done.'
              : 'Held safely by RijHub. ${b.counterpartName.split(' ').first} gets it when you say the job is done.',
        ),
      PaymentState.released => (
          IconsaxPlusBold.tick_circle,
          c.success,
          artisan
              ? 'Paid to your wallet.'
              : 'Paid to ${b.counterpartName.split(' ').first}.'
        ),
      PaymentState.refunded => (
          IconsaxPlusLinear.refresh,
          c.info,
          artisan ? 'Refunded to the client.' : 'Refunded to you.'
        ),
      PaymentState.notPaid => (
          IconsaxPlusLinear.clock,
          c.warning,
          artisan ? 'Not paid yet.' : 'You pay when you confirm the booking.'
        ),
    };
    return Column(
      children: [
        InfoLine(label: b.serviceName, value: Naira.format(price)),
        if (!artisan && b.fee != null)
          InfoLine(label: 'Service fee', value: Naira.format(b.fee!)),
        InfoLine(
            label: artisan ? 'You receive' : 'Total',
            value: Naira.format(artisan ? price : b.total),
            strong: true),
        SizedBox(height: 8.w),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
              color: c.surfaceMuted, borderRadius: BorderRadius.circular(14.w)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18.w, color: color),
              SizedBox(width: 8.w),
              Expanded(child: Text(note, style: AppText.bodySmall)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Copies [text] and says so.
Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, '$what copied');
}
