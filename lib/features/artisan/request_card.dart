import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/media.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../ask/ask_flow.dart';
import '../shared/cards.dart';

/// Minutes left to answer, rounded up so the last minute reads "1 min".
int minutesLeft(DateTime expiresAt) {
  final s = expiresAt.difference(DateTime.now()).inSeconds;
  return s <= 0 ? 0 : (s + 59) ~/ 60;
}

/// A booking request that reads like a message: the client's own words, a
/// photo and a voice note, then the price and the answer. The one card on
/// the artisan's home, because it is a decision with money and a deadline.
class RequestMessageCard extends StatefulWidget {
  const RequestMessageCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReply,
    required this.onOpen,
    this.busy = false,
  });

  final DirectRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReply;
  final VoidCallback onOpen;
  final bool busy;

  @override
  State<RequestMessageCard> createState() => _RequestMessageCardState();
}

class _RequestMessageCardState extends State<RequestMessageCard> {
  late final Timer _tick;
  bool _playing = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _play() {
    final note = widget.request.voiceNote;
    if (note == null) return;
    final media = context.read<MediaService>();
    if (_playing) {
      media.stopPlaying();
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    media.play(note).listen(
      (p) => setState(() => _progress = p),
      onDone: () {
        if (mounted) setState(() => _playing = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.request;
    final left = minutesLeft(r.expiresAt);
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.w),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: widget.onOpen,
            pressedScale: 0.99,
            semanticLabel:
                '${r.clientName} wants ${r.serviceName}, ${windowLabel(r.window)}, ${r.area}. '
                'Offering ${Naira.format(r.price)}. $left minutes left to answer. Open request',
            child: Row(
              children: [
                AppAvatar(
                    name: r.clientName,
                    image: imageFor(r.clientPhoto),
                    size: 40.w),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.clientName,
                          style: AppText.titleSmall
                              .copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${r.serviceName} · ${r.area}${r.distanceKm == null ? '' : ' · ${r.distanceKm!.toStringAsFixed(1)} km'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                StatusTag(
                    label: '$left min',
                    tone: TagTone.warning,
                    icon: IconsaxPlusLinear.timer_1),
              ],
            ),
          ),
          if (r.message != null) ...[
            SizedBox(height: 12.w),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(12.w, 10.w, 12.w, 10.w),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6.w),
                  topRight: Radius.circular(18.w),
                  bottomLeft: Radius.circular(18.w),
                  bottomRight: Radius.circular(18.w),
                ),
              ),
              child: Text(r.message!, style: AppText.body),
            ),
          ],
          if (r.photos.isNotEmpty || r.voiceNote != null) ...[
            SizedBox(height: 8.w),
            Row(
              children: [
                for (final p in r.photos.take(2)) ...[
                  PhotoThumb(image: p, size: 48),
                  SizedBox(width: 8.w),
                ],
                if (r.voiceNote != null)
                  Expanded(
                    child: _VoiceChip(
                      note: r.voiceNote!,
                      playing: _playing,
                      progress: _progress,
                      onTap: _play,
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: 12.w),
          Row(
            children: [
              Icon(IconsaxPlusLinear.calendar_1,
                  size: 16.w, color: c.textSecondary),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(windowLabel(r.window),
                    style: AppText.bodySmall.copyWith(color: c.textSecondary)),
              ),
            ],
          ),
          SizedBox(height: 12.w),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offering',
                      style: AppText.caption.copyWith(color: c.textTertiary)),
                  Text(Naira.format(r.price),
                      style:
                          AppText.title.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const Spacer(),
              AppButton(
                label: 'Reply',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                expand: false,
                semanticLabel: 'Reply to ${r.clientName}',
                onPressed: widget.busy ? null : widget.onReply,
              ),
              SizedBox(width: 8.w),
              AppButton(
                label: 'Accept',
                size: AppButtonSize.small,
                expand: false,
                isLoading: widget.busy,
                semanticLabel: 'Accept ${r.clientName}\'s request',
                onPressed: widget.busy ? null : widget.onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip(
      {required this.note,
      required this.playing,
      required this.progress,
      required this.onTap});

  final VoiceNote note;
  final bool playing;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label:
          '${playing ? 'Pause' : 'Play'} voice note, ${note.duration.inSeconds} seconds'
          '${note.heard == null ? '' : '. ${note.heard}'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48.w,
          padding: EdgeInsets.only(left: 7.w, right: 12.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.w),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration:
                    BoxDecoration(color: c.textPrimary, shape: BoxShape.circle),
                child: Icon(
                    playing ? IconsaxPlusBold.pause : IconsaxPlusBold.play,
                    size: 14.w,
                    color: c.surface),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: ClipRect(
                  child: Waveform(
                    color: c.textPrimary,
                    bars: 18,
                    height: 20,
                    progress: playing ? progress : 0.25,
                    seed: note.path.hashCode,
                  ),
                ),
              ),
              Text(
                '0:${note.duration.inSeconds.toString().padLeft(2, '0')}',
                style: AppText.caption.copyWith(
                    color: c.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A client asking the artisan, by name, for a price.
class PriceRequestCard extends StatelessWidget {
  const PriceRequestCard({super.key, required this.job, required this.onQuote});

  final ClientJob job;
  final VoidCallback onQuote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.w),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TradeIcon(categoryId: job.categoryId, size: 40),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Asked you for a price',
                        style: AppText.caption.copyWith(
                            color: c.brandText, fontWeight: FontWeight.w700)),
                    Text(job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text(RelativeTime.short(job.postedAt),
                  style: AppText.caption.copyWith(color: c.textTertiary)),
            ],
          ),
          if (job.description != null) ...[
            SizedBox(height: 10.w),
            Text(job.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.body),
          ],
          SizedBox(height: 10.w),
          Row(
            children: [
              if (job.photos.isNotEmpty) ...[
                PhotoThumb(image: job.photos.first, size: 44),
                SizedBox(width: 10.w)
              ],
              Expanded(
                child: Text(
                  [job.landmark, job.area].whereType<String>().join(', '),
                  style: AppText.bodySmall.copyWith(color: c.textSecondary),
                ),
              ),
              AppButton(
                  label: 'Send a price',
                  size: AppButtonSize.small,
                  expand: false,
                  onPressed: onQuote),
            ],
          ),
        ],
      ),
    );
  }
}
