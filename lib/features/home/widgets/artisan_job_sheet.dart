import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import '../../auth/widgets/auth_sheet_bar.dart';
import 'artisan_format.dart';
import 'artisan_job_row.dart';

/// Opens [job] over Home: what it is, the budget, where, how fresh, what
/// the client wrote and what we know of them, with one button, "Send
/// quote". [onSendQuote] gets the sheet's context, to ask a guest to sign
/// in over it and to close it.
Future<void> showArtisanJobSheet(
  BuildContext context, {
  required JobPost job,
  required IconData icon,
  required String? tradeName,
  required bool showDistance,
  required bool isGuest,
  required Future<void> Function(BuildContext sheetContext) onSendQuote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The sheet's top row draws the handle, beside close.
    showDragHandle: false,
    barrierLabel: 'Close',
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
    ),
    builder: (_) => DoubleTapGuard(
      child: ArtisanJobSheet(
        job: job,
        icon: icon,
        tradeName: tradeName,
        showDistance: showDistance,
        isGuest: isGuest,
        onSendQuote: onSendQuote,
      ),
    ),
  );
}

/// A job in full, for deciding whether to quote.
class ArtisanJobSheet extends StatelessWidget {
  const ArtisanJobSheet({
    super.key,
    required this.job,
    required this.icon,
    required this.tradeName,
    required this.showDistance,
    required this.isGuest,
    required this.onSendQuote,
  });

  final JobPost job;
  final IconData icon;

  /// The job's trade, "AC repair", once trades have loaded.
  final String? tradeName;
  final bool showDistance;

  /// Guests are told quoting starts with a free profile.
  final bool isGuest;
  final Future<void> Function(BuildContext sheetContext) onSendQuote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final description = job.description;
    final place = showDistance
        ? '${job.area} · ${ArtisanFormat.km(job.distanceKm)} away'
        : job.area;
    final posted = RelativeTime.short(job.postedAt, now: now);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthSheetBar(onClose: () => Navigator.pop(context)),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.s4,
              AppSpace.gutter,
              AppSpace.s16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ArtisanTradeTile(icon: icon),
                    SizedBox(width: AppSpace.s12),
                    Flexible(
                      child: Text(
                        tradeName ?? 'Open job',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.labelSmall.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    if (job.isUrgent) ...[
                      SizedBox(width: AppSpace.s8),
                      const StatusTag(
                        label: 'Urgent',
                        tone: TagTone.warning,
                        icon: IconsaxPlusBold.timer_1,
                      ),
                    ],
                  ],
                ),
                SizedBox(height: AppSpace.s12),
                Semantics(
                  header: true,
                  child: Text(
                    ArtisanFormat.noWidow(job.title),
                    style: AppText.headline.copyWith(color: c.textPrimary),
                  ),
                ),
                SizedBox(height: AppSpace.s8),
                Semantics(
                  label: ArtisanFormat.spokenBudget(
                    job.budgetMin,
                    job.budgetMax,
                  ),
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: ArtisanFormat.budget(
                            job.budgetMin,
                            job.budgetMax,
                          ),
                          style: AppText.title.copyWith(color: c.textPrimary),
                        ),
                        if (job.budgetMin != null || job.budgetMax != null)
                          TextSpan(
                            text: "  client's budget",
                            style: AppText.bodySmall.copyWith(
                              color: c.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: AppSpace.s16),
                _Fact(
                  icon: IconsaxPlusLinear.location,
                  text: place,
                  spoken: showDistance
                      ? '${job.area}, ${ArtisanFormat.spokenKm(job.distanceKm)}'
                      : null,
                ),
                _Fact(
                  icon: IconsaxPlusLinear.clock_1,
                  text: 'Posted ${TextCase.midSentence(posted)}',
                  spoken: 'Posted ${TextCase.midSentence(
                    RelativeTime.spoken(job.postedAt, now: now),
                  )}',
                ),
                _Fact(
                  icon: IconsaxPlusLinear.profile_2user,
                  text: ArtisanJobRow.quotes(job.quoteCount),
                  color: job.quoteCount == 0 ? c.success : null,
                ),
                if (description != null) ...[
                  SizedBox(height: AppSpace.s12),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(AppSpace.s16),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: AppRadius.lgAll,
                    ),
                    child: Text(
                      description,
                      style: AppText.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
                SizedBox(height: AppSpace.s16),
                _ClientSignals(job: job),
              ],
            ),
          ),
        ),
        _SendBar(
          isGuest: isGuest,
          onSend: () => onSendQuote(context),
        ),
      ],
    );
  }
}

/// One fact about the job: an icon and a short line.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.text,
    this.spoken,
    this.color,
  });

  final IconData icon;
  final String text;

  /// What screen readers say, when [text] has symbols in it.
  final String? spoken;

  /// Defaults to the secondary text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = color ?? c.textSecondary;
    return Semantics(
      label: spoken ?? text,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 3.w),
        child: Row(
          children: [
            Icon(icon, size: AppSize.iconSmall, color: ink),
            SizedBox(width: AppSpace.s8),
            Expanded(
              child: Text(
                text,
                style: AppText.body.copyWith(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What we know of the client: whether their phone is verified and how
/// many jobs they have posted.
class _ClientSignals extends StatelessWidget {
  const _ClientSignals({required this.job});

  final JobPost job;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final verified = job.clientPhoneVerified;
    final posted = job.clientJobsPosted;
    final history =
        posted <= 1 ? 'First job on RijHub' : '$posted jobs posted on RijHub';
    return Semantics(
      label: 'About the client: ${verified ? 'phone verified' : 'phone not '
          'verified yet'}. $history.',
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: 32.w,
            height: 32.w,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              IconsaxPlusLinear.profile_circle,
              size: 18.w,
              color: c.textSecondary,
            ),
          ),
          SizedBox(width: AppSpace.s12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (verified) ...[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        IconsaxPlusBold.tick_circle,
                        size: 14.w,
                        color: c.success,
                      ),
                    ),
                    TextSpan(
                      text: '\u00A0Phone verified',
                      style: TextStyle(color: c.textPrimary),
                    ),
                  ] else
                    const TextSpan(text: 'Phone not verified yet'),
                  TextSpan(text: ' · $history'),
                ],
              ),
              style: AppText.bodySmall.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's one action, kept in view below the scrolling details.
class _SendBar extends StatelessWidget {
  const _SendBar({required this.isGuest, required this.onSend});

  final bool isGuest;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: AppSpace.s12),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s12,
            AppSpace.gutter,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(label: 'Send quote', onPressed: onSend),
              if (isGuest) ...[
                SizedBox(height: AppSpace.s8),
                Text(
                  "Free to join. You'll add your phone number to send it.",
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
