import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/media.dart';
import '../../app/routes.dart';
import '../../app/push.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// A conversation with an artisan or a client: words, photos and voice
/// notes, with the booking it is about pinned at the top.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  Conversation? _convo;
  Booking? _booking;
  late final Stream<List<ChatMessage>> _messages =
      context.read<ChatRepository>().watch(widget.conversationId);
  int _count = 0;
  bool _recording = false;

  Object? _playing;
  double _progress = 0;
  StreamSubscription<double>? _play;

  @override
  void initState() {
    super.initState();
    OpenChat.id = widget.conversationId;
    _load();
  }

  Future<void> _load() async {
    final chat = context.read<ChatRepository>();
    final bookings = context.read<BookingFlowRepository>();
    final convo = await chat.byId(widget.conversationId);
    await chat.markRead(widget.conversationId);
    Booking? booking;
    if (convo.bookingId != null) {
      try {
        booking = await bookings.byId(convo.bookingId!);
      } on Object {
        booking = null;
      }
    }
    if (mounted) {
      setState(() {
        _convo = convo;
        _booking = booking;
      });
    }
  }

  @override
  void dispose() {
    if (OpenChat.id == widget.conversationId) OpenChat.id = null;
    _play?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: context.motion(AppMotion.base),
        curve: AppMotion.standard,
      );
    });
  }

  Future<void> _send({String? text, VoiceNote? voice, String? photo}) async {
    final chat = context.read<ChatRepository>();
    await chat.send(widget.conversationId,
        text: text, voiceNote: voice, photo: photo);
    await chat.markRead(widget.conversationId);
  }

  Future<void> _photo() async {
    final path = await context.read<MediaService>().pickPhoto(camera: true);
    if (path != null) await _send(photo: path);
  }

  Future<void> _startVoice() async {
    final ok = await context.read<MediaService>().startRecording();
    if (!mounted) return;
    if (!ok) {
      showToast(
          context, 'Allow the microphone in Settings to send voice notes.',
          error: true);
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _sendVoice() async {
    final note = await context.read<MediaService>().stopRecording();
    setState(() => _recording = false);
    if (note != null) await _send(voice: note);
  }

  Future<void> _cancelVoice() async {
    await context.read<MediaService>().cancelRecording();
    setState(() => _recording = false);
  }

  void _togglePlay(ChatMessage m) {
    final media = context.read<MediaService>();
    _play?.cancel();
    if (_playing == m.id) {
      media.stopPlaying();
      setState(() => _playing = null);
      return;
    }
    setState(() {
      _playing = m.id;
      _progress = 0;
    });
    _play = media.play(m.voiceNote!).listen(
      (p) => setState(() => _progress = p),
      onDone: () {
        if (mounted) setState(() => _playing = null);
      },
    );
  }

  Future<void> _call() async {
    final phone = _booking?.counterpartPhone;
    if (phone != null) await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final convo = _convo;
    final booking = _booking;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(4.w, 4.w, 8.w, 6.w),
              child: Row(
                children: [
                  AppIconButton(
                    icon: IconsaxPlusLinear.arrow_left,
                    semanticLabel: 'Back',
                    onPressed: () => goBack(context),
                  ),
                  if (convo != null) ...[
                    AppAvatar(
                        name: convo.title,
                        image: imageFor(convo.photo),
                        size: 40.w),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(convo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.titleSmall
                                  .copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            convo.online ? 'Online' : (convo.subtitle ?? ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                                color:
                                    convo.online ? c.success : c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (booking?.counterpartPhone != null &&
                        !(booking?.isOver ?? true))
                      AppIconButton(
                          icon: IconsaxPlusLinear.call,
                          semanticLabel: 'Call ${convo.title}',
                          onPressed: _call),
                    if (convo.artisanId != null && booking == null)
                      AppIconButton(
                        icon: IconsaxPlusLinear.profile_circle,
                        semanticLabel: 'See profile',
                        onPressed: () =>
                            context.push(Routes.artisan(convo.artisanId!)),
                      ),
                  ] else
                    const Spacer(),
                ],
              ),
            ),
            if (booking != null) _BookingStrip(booking: booking),
            Divider(height: 1, thickness: 1, color: c.border),
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messages,
                builder: (context, snap) {
                  final list = snap.data ?? const <ChatMessage>[];
                  if (list.length != _count) {
                    _count = list.length;
                    _toBottom();
                  }
                  if (!snap.hasData) return const SizedBox.shrink();
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpace.s32),
                        child: Text(
                          'Say hello. You can send photos and voice notes too.',
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(color: c.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                        AppSpace.gutter, 12.w, AppSpace.gutter, 12.w),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final m = list[i];
                      final newDay =
                          i == 0 || !_sameDay(list[i - 1].sentAt, m.sentAt);
                      final lastOfRun = i == list.length - 1 ||
                          list[i + 1].fromMe != m.fromMe;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) _DayChip(day: m.sentAt),
                          switch (m.kind) {
                            MessageKind.system => SystemNote(m.text ?? ''),
                            MessageKind.voice => VoiceNoteBubble(
                                mine: m.fromMe,
                                duration: m.voiceNote!.duration,
                                heard: m.voiceNote!.heard,
                                playing: _playing == m.id,
                                progress: _playing == m.id ? _progress : 0,
                                onPlay: () => _togglePlay(m),
                                seed: m.id.hashCode,
                              ),
                            MessageKind.photo => PhotoBubble(
                                image: m.photo!,
                                mine: m.fromMe,
                                caption: m.text),
                            _ => ChatBubble(
                                text: m.text ?? '',
                                mine: m.fromMe,
                                meta: lastOfRun
                                    ? '${Schedule.time(m.sentAt)}${m.fromMe ? (m.read ? ' · Seen' : ' · Sent') : ''}'
                                    : null,
                              ),
                          },
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, 6.w, AppSpace.gutter, 8.w),
              child: Composer(
                hint: 'Message',
                recording: _recording,
                level: context.read<MediaService>().level,
                onSend: (t) => _send(text: t),
                onCamera: _photo,
                onVoiceStart: _startVoice,
                onVoiceCancel: _cancelVoice,
                onVoiceSend: _sendVoice,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8.w),
        child: Center(
          child: Text(
            Schedule.dayLabel(day),
            style: AppText.caption.copyWith(
                color: context.colors.textTertiary,
                fontWeight: FontWeight.w600),
          ),
        ),
      );
}

class _BookingStrip extends StatelessWidget {
  const _BookingStrip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, tone) =
        bookingStatus(booking, artisan: booking.startCode == null);
    return Pressable(
      onTap: () => context.push(Routes.booking(booking.id)),
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${booking.serviceName}, ${Schedule.dayAndTime(booking.scheduledAt)}, $label. Open booking',
      child: Container(
        margin: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, 8.w),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
        decoration: BoxDecoration(
            color: c.surfaceMuted, borderRadius: BorderRadius.circular(14.w)),
        child: Row(
          children: [
            TradeIcon(categoryId: booking.categoryId, size: 34),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelSmall),
                  Text(Schedule.dayAndTime(booking.scheduledAt),
                      style: AppText.caption.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            StatusTag(label: label, tone: tone),
            SizedBox(width: 4.w),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 16.w, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
