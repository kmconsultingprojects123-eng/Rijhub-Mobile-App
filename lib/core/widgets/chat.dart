import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import '../utils/images.dart';
import 'brand.dart';

/// Pieces of a conversation: bubbles, voice notes, photos, notes from the
/// system, and RijHub typing. Mine are crimson on the right; theirs are grey
/// on the left.

BorderRadius _bubbleRadius(bool mine) => BorderRadius.only(
      topLeft: Radius.circular(20.w),
      topRight: Radius.circular(20.w),
      bottomLeft: Radius.circular(mine ? 20.w : 6.w),
      bottomRight: Radius.circular(mine ? 6.w : 20.w),
    );

/// The widest a bubble gets: three quarters of the screen.
double _maxBubble(BuildContext context) =>
    MediaQuery.sizeOf(context).width * 0.76;

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    this.mine = false,
    this.meta,
  });

  final String text;
  final bool mine;

  /// A time or "Seen" under the bubble.
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 8.w),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: _maxBubble(context)),
              padding: EdgeInsets.fromLTRB(14.w, 10.w, 14.w, 10.w),
              decoration: BoxDecoration(
                color: mine ? c.brand : c.surfaceMuted,
                borderRadius: _bubbleRadius(mine),
              ),
              child: Text(
                text,
                style: AppText.body.copyWith(
                  color: mine ? c.onBrand : c.textPrimary,
                ),
              ),
            ),
            if (meta != null)
              Padding(
                padding: EdgeInsets.only(top: 3.w, left: 4.w, right: 4.w),
                child: Text(
                  meta!,
                  style: AppText.caption.copyWith(color: c.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of bars drawn from a seed, so a voice note always looks the same.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.color,
    this.bars = 26,
    this.height = 22,
    this.progress = 1,
    this.seed = 7,
  });

  final Color color;
  final int bars;
  final double height;

  /// 0 to 1: how much has played. Played bars are solid.
  final double progress;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(seed);
    final heights = [
      for (var i = 0; i < bars; i++)
        0.28 +
            0.72 *
                (0.5 + 0.5 * math.sin(i * 0.9 + rnd.nextDouble() * 2.4)).abs(),
    ];
    return SizedBox(
      height: height.w,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < bars; i++)
            Container(
              width: 2.6.w,
              height: height.w * heights[i],
              margin: EdgeInsets.only(right: 2.2.w),
              decoration: BoxDecoration(
                color:
                    i / bars < progress ? color : color.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// A voice note: play, the waveform, how long it is, and what RijHub heard
/// in it when it was transcribed.
class VoiceNoteBubble extends StatelessWidget {
  const VoiceNoteBubble({
    super.key,
    required this.duration,
    this.mine = false,
    this.heard,
    this.playing = false,
    this.progress = 0,
    this.onPlay,
    this.seed = 7,
  });

  final Duration duration;
  final bool mine;
  final String? heard;
  final bool playing;

  /// 0 to 1.
  final double progress;
  final VoidCallback? onPlay;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = mine ? c.onBrand : c.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 8.w),
        child: Container(
          constraints: BoxConstraints(maxWidth: _maxBubble(context)),
          padding: EdgeInsets.fromLTRB(8.w, 8.w, 14.w, 10.w),
          decoration: BoxDecoration(
            color: mine ? c.brand : c.surfaceMuted,
            borderRadius: _bubbleRadius(mine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: playing ? 'Pause voice note' : 'Play voice note',
                    child: GestureDetector(
                      onTap: onPlay,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(2.w),
                        child: Container(
                          width: 36.w,
                          height: 36.w,
                          decoration: BoxDecoration(
                            color: mine
                                ? Colors.white.withValues(alpha: 0.18)
                                : c.textPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            playing
                                ? IconsaxPlusBold.pause
                                : IconsaxPlusBold.play,
                            size: 16.w,
                            color: mine ? c.onBrand : c.surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: ExcludeSemantics(
                      child: Waveform(
                        color: fg,
                        progress: playing || progress > 0 ? progress : 1,
                        seed: seed,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    _clock(duration),
                    style: AppText.caption.copyWith(
                      color: fg.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (heard != null) ...[
                SizedBox(height: 8.w),
                Padding(
                  padding: EdgeInsets.only(left: 6.w),
                  child: Text(
                    '“$heard”',
                    style: AppText.bodySmall.copyWith(
                      color: fg.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo someone sent.
class PhotoBubble extends StatelessWidget {
  const PhotoBubble({
    super.key,
    required this.image,
    this.mine = false,
    this.caption,
    this.onTap,
  });

  final String image;
  final bool mine;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final provider = imageFor(image);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 8.w),
        child: Semantics(
          image: true,
          button: onTap != null,
          label: caption ?? 'Photo',
          child: GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: _bubbleRadius(mine),
              child: Container(
                width: 220.w,
                color: c.surfaceMuted,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider != null)
                      Image(
                        image: provider,
                        width: 220.w,
                        height: 160.w,
                        fit: BoxFit.cover,
                      ),
                    if (caption != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(12.w, 8.w, 12.w, 10.w),
                        child: Text(caption!, style: AppText.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet line from the system between messages: "Booking confirmed".
class SystemNote extends StatelessWidget {
  const SystemNote(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.w),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.w),
          constraints: BoxConstraints(maxWidth: _maxBubble(context) + 20.w),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon ?? IconsaxPlusLinear.shield_tick,
                  size: 14.w, color: c.success),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RijHub thinking: three dots in a bubble.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'RijHub is typing',
        child: Container(
          margin: EdgeInsets.only(bottom: 8.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.w),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: _bubbleRadius(false),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7.w,
                    height: 7.w,
                    margin: EdgeInsets.only(right: i < 2 ? 5.w : 0),
                    decoration: BoxDecoration(
                      color: c.textTertiary.withValues(
                        alpha: 0.35 +
                            0.65 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                            (_controller.value * 2 * math.pi) -
                                                i * 0.9)),
                      ),
                      shape: BoxShape.circle,
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

/// A card inside a conversation: a map, a match, a booking.
class CardMessage extends StatelessWidget {
  const CardMessage({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: 8.w),
      child: Container(
        width: double.infinity,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20.w),
          border: Border.all(color: c.border),
        ),
        child: child,
      ),
    );
  }
}

/// RijHub's own avatar: the mark in a crimson circle.
class RijHubAvatar extends StatelessWidget {
  const RijHubAvatar({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size.w,
      height: size.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
      child: RijHubMark(size: size.w * 0.52, white: true),
    );
  }
}

/// The bar a voice note is recorded in: a red dot, the time so far, the
/// live level, and cancel / send.
class RecordingBar extends StatefulWidget {
  const RecordingBar({
    super.key,
    required this.onCancel,
    required this.onSend,
    this.level,
  });

  final VoidCallback onCancel;
  final VoidCallback onSend;

  /// The microphone's level, 0 to 1, as it changes.
  final Stream<double>? level;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  final _started = DateTime.now();
  late final Timer _tick;
  final _levels = <double>[];
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    _sub = widget.level?.listen((v) {
      _levels.add(v);
      if (_levels.length > 28) _levels.removeAt(0);
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final elapsed = DateTime.now().difference(_started);
    return Container(
      height: 56.w,
      padding: EdgeInsets.only(left: 6.w, right: 6.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: c.brandStroke, width: 1.5),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Cancel voice note',
            child: GestureDetector(
              onTap: widget.onCancel,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44.w,
                height: 44.w,
                child: Icon(IconsaxPlusLinear.trash,
                    size: 20.w, color: c.textSecondary),
              ),
            ),
          ),
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(color: c.error, shape: BoxShape.circle),
          ),
          SizedBox(width: 8.w),
          Text(
            _clock(elapsed),
            style: AppText.labelSmall.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: ExcludeSemantics(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ClipRect(
                  child: Waveform(
                    color: c.brandStroke,
                    bars: 22,
                    seed: elapsed.inMilliseconds ~/ 400,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Send voice note',
            child: GestureDetector(
              onTap: widget.onSend,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44.w,
                height: 44.w,
                decoration:
                    BoxDecoration(color: c.brand, shape: BoxShape.circle),
                child: Icon(IconsaxPlusLinear.arrow_up,
                    size: 22.w, color: c.onBrand),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
