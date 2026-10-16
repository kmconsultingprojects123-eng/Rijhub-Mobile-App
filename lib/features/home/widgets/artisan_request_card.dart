import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import 'artisan_format.dart';
import 'artisan_meta_line.dart';

/// Under this many minutes, the reply-by countdown turns red.
const _urgentMinutes = 3;

/// How a request is being answered, while the answer is sent.
enum RequestAnswer { accepting, declining }

/// A client who picked this artisan and is waiting for a yes: who, what,
/// when, where and the price, with a reply-by countdown, "Not now" and
/// "Accept". The one card on Home that holds a decision with money and a
/// deadline, so it is the one with a tint. When the time asked for clashes
/// with one of the artisan's own bookings, it says so before they accept.
class ArtisanRequestCard extends StatelessWidget {
  const ArtisanRequestCard({
    super.key,
    required this.request,
    required this.now,
    required this.onAccept,
    required this.onDecline,
    this.answering,
    this.clashesWith,
  });

  final DirectRequest request;
  final DateTime now;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Set while an answer is on its way; both buttons wait for it.
  final RequestAnswer? answering;

  /// The start of a booking the artisan already has inside the time asked
  /// for, if there is one.
  final DateTime? clashesWith;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final minutes = ArtisanFormat.minutesLeft(request.expiresAt, now);
    final day = Schedule.dayLabel(request.window.start, now: now);
    final busy = answering != null;
    final client = request.clientName;
    final clash = clashesWith == null
        ? null
        : 'Clashes with your ${ArtisanFormat.clock(clashesWith!)} job';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        // Words start where the today card's do, inside its 1pt border and
        // 12pt padding, so the two cards line up.
        padding: EdgeInsetsDirectional.fromSTEB(12.w + 1, 12.w, 12.w, 6.w),
        decoration: BoxDecoration(
          color: c.brandSubtle,
          borderRadius: AppRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: '$client wants to book you: ${request.serviceName}, '
                  '${TextCase.midSentence(day)} '
                  '${ArtisanFormat.spokenWindow(request.window)}, '
                  '${request.area}, ${Naira.format(request.price)}. '
                  '${_spokenLeft(minutes)}'
                  '${clash == null ? '' : ' $clash.'}',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // "book you" stays together if the line breaks.
                            '$client wants to book\u00A0you',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.titleSmall.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpace.s8),
                        _Countdown(minutes: minutes),
                      ],
                    ),
                    SizedBox(height: AppSpace.s4),
                    // The price ends the line, and with large text the
                    // line breaks between facts rather than leaving it on
                    // its own after a dot.
                    ArtisanMetaLine(
                      style: AppText.bodySmall.copyWith(
                        color: c.textSecondary,
                      ),
                      facts: [
                        TextSpan(text: request.serviceName),
                        TextSpan(
                          text: '$day\u00A0'
                              '${ArtisanFormat.window(request.window)}',
                        ),
                        TextSpan(text: request.area),
                        TextSpan(
                          text: Naira.format(request.price),
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (clash != null) ...[
                      SizedBox(height: AppSpace.s4),
                      _ClashNote(text: clash),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: AppSpace.s4),
            Row(
              children: [
                _QuietButton(
                  label: 'Not now',
                  semanticLabel: "Not now: turn down $client's request",
                  onPressed: busy ? null : onDecline,
                ),
                const Spacer(),
                SizedBox(
                  width: 120.w,
                  child: AppButton(
                    label: 'Accept',
                    semanticLabel: "Accept $client's request",
                    size: AppButtonSize.small,
                    isLoading: answering == RequestAnswer.accepting,
                    onPressed: busy ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _spokenLeft(int minutes) => minutes == 1
      ? '1 minute left to answer.'
      : '$minutes minutes left to answer.';
}

/// "Clashes with your 10:51 PM job", in the warning colour with its mark
/// beside the first line.
class _ClashNote extends StatelessWidget {
  const _ClashNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppText.bodySmall.copyWith(
      color: c.warning,
      fontWeight: FontWeight.w600,
    );
    final firstLine =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: firstLine,
          child: Icon(
            IconsaxPlusLinear.warning_2,
            size: AppSize.iconSmall,
            color: c.warning,
          ),
        ),
        SizedBox(width: AppSpace.s6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// "Not now": words in the secondary text colour with a 48pt touch area,
/// so Accept stays the card's one strong action. The words line up with
/// the card's text; the touch area reaches past them on the far side.
class _QuietButton extends StatelessWidget {
  const _QuietButton({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;

  /// Null while an answer is on its way.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      focusRadius: AppRadius.mdAll,
      focusOffset: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSize.minTapTarget,
          minHeight: AppSize.minTapTarget,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(end: AppSpace.s20),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: AppText.labelSmall.copyWith(
                color: onPressed == null ? c.textDisabled : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "⏱ 14 min": how long is left to answer. Amber, and red near the end.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = minutes < _urgentMinutes;
    final ink = urgent ? c.error : c.warning;
    return Container(
      constraints: BoxConstraints(minHeight: AppSpace.s24),
      padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusBold.timer, size: 13.w, color: ink),
          SizedBox(width: AppSpace.s4),
          Text(
            '$minutes\u00A0min',
            style: AppText.caption.copyWith(
              color: ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
