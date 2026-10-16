import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models/models.dart';
import '../../auth/widgets/auth_sheet_bar.dart';
import 'artisan_format.dart';

/// What the artisan chose: available now ([available]), busy until
/// [busyUntil], or off (neither).
typedef ArtisanAvailability = ({bool available, DateTime? busyUntil});

/// The busy spells on offer, in hours.
const _busyHours = [1, 2, 3];

/// Opens the availability sheet. Resolves to the artisan's choice, or null
/// if they closed it without one.
///
/// [demand] is one line on how much work there is today, to help decide.
/// While [blockingStep] is unfinished (the ID check) clients can't book
/// the artisan at all, so the options wait and the sheet offers that step
/// through [onStartSetup].
Future<ArtisanAvailability?> showArtisanAvailabilitySheet(
  BuildContext context, {
  required AvailabilityStatus status,
  DateTime? busyUntil,
  String? demand,
  SetupStep? blockingStep,
  VoidCallback? onStartSetup,
}) {
  return showModalBottomSheet<ArtisanAvailability>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    barrierLabel: 'Close',
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => DoubleTapGuard(
      child: ArtisanAvailabilitySheet(
        status: status,
        busyUntil: busyUntil,
        demand: demand,
        blockingStep: blockingStep,
        onStartSetup: onStartSetup,
      ),
    ),
  );
}

/// The sheet's content: a title, the day's demand, and the three states.
/// Choosing one closes the sheet with it; "Busy until…" first asks for how
/// long.
class ArtisanAvailabilitySheet extends StatefulWidget {
  const ArtisanAvailabilitySheet({
    super.key,
    required this.status,
    this.busyUntil,
    this.demand,
    this.blockingStep,
    this.onStartSetup,
  });

  final AvailabilityStatus status;
  final DateTime? busyUntil;
  final String? demand;
  final SetupStep? blockingStep;
  final VoidCallback? onStartSetup;

  /// [hours] from now, rounded up to the next quarter hour, so a busy
  /// spell ends at a time people say: "until 4:30 PM".
  static DateTime busyFor(int hours, {DateTime? from}) {
    final end = (from ?? DateTime.now()).add(Duration(hours: hours));
    final pastHour = Duration(
      minutes: end.minute,
      seconds: end.second,
      milliseconds: end.millisecond,
      microseconds: end.microsecond,
    );
    final quarters = (pastHour.inSeconds + 899) ~/ 900;
    return DateTime(end.year, end.month, end.day, end.hour)
        .add(Duration(minutes: quarters * 15));
  }

  @override
  State<ArtisanAvailabilitySheet> createState() =>
      _ArtisanAvailabilitySheetState();
}

class _ArtisanAvailabilitySheetState extends State<ArtisanAvailabilitySheet> {
  /// The busy option's durations show: it was tapped, or the artisan is
  /// busy now and may want a different end.
  late bool _pickingBusy = widget.status == AvailabilityStatus.busy;

  bool get _blocked => widget.blockingStep != null;

  void _choose(ArtisanAvailability choice) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final until = widget.busyUntil;
    final busyNow = widget.status == AvailabilityStatus.busy && until != null;
    final demand = widget.demand;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: AppSpace.s16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthSheetBar(onClose: () => Navigator.pop(context)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Your availability',
                      style: AppText.headline.copyWith(color: c.textPrimary),
                    ),
                  ),
                  if (demand != null) ...[
                    SizedBox(height: AppSpace.s4),
                    Row(
                      children: [
                        Icon(
                          IconsaxPlusLinear.trend_up,
                          size: AppSize.iconSmall,
                          color: c.success,
                        ),
                        SizedBox(width: AppSpace.s6),
                        Expanded(
                          child: Text(
                            demand,
                            style: AppText.bodySmall.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: AppSpace.s12),
                  if (widget.blockingStep case final step?) ...[
                    InlineNote(
                      icon: IconsaxPlusLinear.personalcard,
                      iconColor: c.warning,
                      title: step.id == 'identity'
                          ? 'Verify your ID first'
                          : '${step.label} first',
                      message: "Clients can book you once that's done. "
                          'You can quote on jobs now.',
                    ),
                    SizedBox(height: AppSpace.s8),
                  ],
                ],
              ),
            ),
            _Option(
              status: AvailabilityStatus.available,
              label: 'Available now',
              hint: 'Clients can book you',
              selected: widget.status == AvailabilityStatus.available,
              enabled: !_blocked,
              onTap: () => _choose((available: true, busyUntil: null)),
            ),
            _Option(
              status: AvailabilityStatus.busy,
              label: busyNow
                  ? 'Busy until ${ArtisanFormat.clock(until)}'
                  : 'Busy until…',
              spokenLabel: busyNow ? null : 'Busy until a time you pick',
              hint: 'Available again by itself',
              selected: widget.status == AvailabilityStatus.busy,
              enabled: !_blocked,
              onTap: () => setState(() => _pickingBusy = true),
            ),
            if (_pickingBusy && !_blocked)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _Option.textStart,
                  end: AppSpace.gutter,
                ),
                // The end of each spell, so the row reads "Busy until… 5:30
                // PM", as clients will see it.
                child: Wrap(
                  spacing: AppSpace.s8,
                  children: [
                    for (final hours in _busyHours)
                      AppChip(
                        label: ArtisanFormat.clock(
                          ArtisanAvailabilitySheet.busyFor(hours),
                        ),
                        selected: false,
                        singleChoice: true,
                        onTap: () => _choose((
                          available: false,
                          busyUntil: ArtisanAvailabilitySheet.busyFor(hours),
                        )),
                      ),
                  ],
                ),
              ),
            _Option(
              status: AvailabilityStatus.off,
              label: 'Off',
              hint: 'Until you switch back',
              selected: widget.status == AvailabilityStatus.off,
              enabled: !_blocked,
              onTap: () => _choose((available: false, busyUntil: null)),
            ),
            if (_blocked && widget.onStartSetup != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.s16,
                  AppSpace.gutter,
                  0,
                ),
                child: AppButton(
                  label: widget.blockingStep!.id == 'identity'
                      ? 'Verify your ID'
                      : widget.blockingStep!.label,
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onStartSetup!();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One state, as a 56pt radio row: its dot, its name and what it means.
class _Option extends StatelessWidget {
  const _Option({
    required this.status,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.spokenLabel,
  });

  final AvailabilityStatus status;
  final String label;

  /// What screen readers say for [label], where it has symbols in it.
  final String? spokenLabel;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Where the words start, from the sheet's edge.
  static double get textStart => AppSpace.gutter + 20.w + AppSpace.s12;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dotColor = switch (status) {
      AvailabilityStatus.available => c.online,
      AvailabilityStatus.busy => c.warning,
      AvailabilityStatus.off => null,
    };
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: enabled,
        child: Pressable(
          onTap: enabled ? onTap : null,
          semanticLabel: '${spokenLabel ?? label}. $hint',
          pressedScale: 0.99,
          focusRadius: BorderRadius.zero,
          focusOffset: 0,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 56.w),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpace.gutter,
                  vertical: AppSpace.s8,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 20.w,
                      child: Center(
                        child: Container(
                          width: 10.w,
                          height: 10.w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor,
                            border: dotColor == null
                                ? Border.all(color: c.textTertiary, width: 1.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: AppText.titleSmall.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            hint,
                            style: AppText.bodySmall.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpace.s12),
                    _Radio(selected: selected),
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

/// The app's radio mark, as on selection cards: a ring, filled with a tick
/// when chosen.
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = 22.w;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.brandStroke : Colors.transparent,
        border: Border.all(
          color: selected ? c.brandStroke : c.borderStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15.w, color: c.onBrand)
          : null,
    );
  }
}
