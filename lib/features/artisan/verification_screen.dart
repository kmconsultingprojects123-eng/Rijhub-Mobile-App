import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/media.dart';
import '../../app/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../booking/booking_sheets.dart';
import '../shared/page.dart';

/// Clients only book ID-checked artisans, so a quote waits for the check to
/// be under way. True when it's done or being checked; otherwise offers to
/// start it, and returns false.
Future<bool> ensureVerified(BuildContext context) async {
  final check = await context.read<ArtisanSetupRepository>().verification();
  if (check.state == VerificationState.verified ||
      check.state == VerificationState.pending) {
    return true;
  }
  if (!context.mounted) return false;
  final start = await confirmSheet(
    context,
    title: 'Get verified to quote',
    message: 'Clients only book artisans whose ID is checked. It takes about '
        '2 minutes: your NIN and a selfie.',
    confirm: 'Start ID check',
    cancel: 'Not now',
  );
  if (start && context.mounted) await context.push(Routes.verification);
  return false;
}

/// The ID check: an artisan's NIN matched to a live selfie. Clients can
/// book them once it passes.
///
/// The selfie and liveness check run in the identity partner's screen
/// (Dojah) once the backend starts a session; until then the camera takes
/// the selfie here.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

enum _Step { intro, nin, selfie }

class _VerificationScreenState extends State<VerificationScreen> {
  Verification? _status;
  _Step _step = _Step.intro;
  final _nin = TextEditingController();
  String? _selfie;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await context.read<ArtisanSetupRepository>().verification();
    if (mounted) setState(() => _status = v);
  }

  @override
  void dispose() {
    _nin.dispose();
    super.dispose();
  }

  Future<void> _takeSelfie() async {
    final path = await context.read<MediaService>().pickPhoto(camera: true);
    if (path != null) setState(() => _selfie = path);
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final v = await context
          .read<ArtisanSetupRepository>()
          .submitVerification(nin: _nin.text, selfie: _selfie!);
      if (mounted) setState(() => _status = v);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _step = _Step.nin;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return const PageScaffold(title: 'ID check', body: ListSkeleton());
    }
    return switch (status.state) {
      VerificationState.verified => _Result(
          icon: IconsaxPlusBold.verify,
          color: context.colors.verified,
          title: "You're verified",
          message:
              'Clients see the verified badge on your profile, and they can book you. '
              '${status.updatedAt == null ? '' : 'Checked ${Schedule.dayLabel(status.updatedAt!)}.'}',
        ),
      VerificationState.pending => _Result(
          icon: IconsaxPlusLinear.clock,
          color: context.colors.info,
          title: 'We\'re checking your ID',
          message:
              'Most checks finish in a few minutes. We\'ll tell you as soon as it\'s done; you can keep quoting meanwhile.',
          action: AppButton(
              label: 'Check again',
              variant: AppButtonVariant.secondary,
              onPressed: _load),
        ),
      VerificationState.failed => _Result(
          icon: IconsaxPlusLinear.danger,
          color: context.colors.warning,
          title: 'It didn\'t match',
          message: status.reason ??
              'Your selfie didn\'t match the photo on your NIN record. Try again in good light, without glasses or a cap.',
          action: AppButton(
              label: 'Try again',
              onPressed: () => setState(() => _status =
                  const Verification(state: VerificationState.notStarted))),
        ),
      VerificationState.notStarted => _flow(context),
    };
  }

  Widget _flow(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    switch (_step) {
      case _Step.intro:
        Widget point(IconData icon, String title, String body) => Padding(
              padding: EdgeInsets.only(bottom: 16.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                        color: c.surfaceMuted,
                        borderRadius: BorderRadius.circular(14.w)),
                    child: Icon(icon, size: 20.w),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.titleSmall),
                        Text(body,
                            style: AppText.bodySmall
                                .copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
        return PageScaffold(
          title: 'ID check',
          bottom: AppButton(
              label: 'Start',
              onPressed: () => setState(() => _step = _Step.nin)),
          body: ListView(
            padding: EdgeInsets.fromLTRB(g, 8.w, g, 24.w),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(IconsaxPlusBold.verify,
                      size: 48.w, color: c.verified)),
              SizedBox(height: 12.w),
              Text('Get verified to get booked', style: AppText.headline),
              SizedBox(height: 6.w),
              Text(
                  'It takes about 2 minutes. Clients book verified artisans far more often.',
                  style: AppText.body.copyWith(color: c.textSecondary)),
              SizedBox(height: 22.w),
              point(IconsaxPlusLinear.personalcard, 'Your NIN',
                  'The 11-digit number on your National ID slip or card.'),
              point(IconsaxPlusLinear.camera, 'A quick selfie',
                  'Somewhere bright, without glasses or a cap.'),
              point(IconsaxPlusLinear.shield_tick, 'Kept private',
                  'Used only to confirm it\'s you. Clients see the badge, never your NIN.'),
            ],
          ),
        );
      case _Step.nin:
        final valid = _nin.text.length == 11;
        return PageScaffold(
          title: 'Your NIN',
          onBack: () => setState(() => _step = _Step.intro),
          bottom: AppButton(
              label: 'Continue',
              onPressed:
                  valid ? () => setState(() => _step = _Step.selfie) : null),
          body: ListView(
            padding: EdgeInsets.fromLTRB(g, 8.w, g, 24.w),
            children: [
              const StepProgress(step: 1, total: 2),
              SizedBox(height: 20.w),
              Text('Enter your NIN', style: AppText.headline),
              SizedBox(height: 6.w),
              Text('Your National Identification Number.',
                  style: AppText.body.copyWith(color: c.textSecondary)),
              SizedBox(height: 16.w),
              AppTextField(
                controller: _nin,
                label: 'NIN',
                hint: '11 digits',
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11)
                ],
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
              SizedBox(height: 12.w),
              InlineNote(
                icon: IconsaxPlusLinear.mobile,
                title: "Don't have it to hand?",
                message:
                    'Dial *346# from the phone number you registered your NIN with.',
              ),
            ],
          ),
        );
      case _Step.selfie:
        final photo = _selfie;
        return PageScaffold(
          title: 'Selfie',
          onBack: () => setState(() => _step = _Step.nin),
          bottom: photo == null
              ? AppButton(
                  label: 'Take selfie',
                  leading: const Icon(IconsaxPlusLinear.camera),
                  onPressed: _takeSelfie)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                        label: 'Send for checking',
                        isLoading: _sending,
                        onPressed: _sending ? null : _submit),
                    AppButton(
                        label: 'Retake',
                        variant: AppButtonVariant.tertiary,
                        onPressed: _takeSelfie),
                  ],
                ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(g, 8.w, g, 24.w),
            children: [
              const StepProgress(step: 2, total: 2),
              SizedBox(height: 20.w),
              Text('Take a selfie', style: AppText.headline),
              SizedBox(height: 6.w),
              Text('Look straight at the camera, in good light.',
                  style: AppText.body.copyWith(color: c.textSecondary)),
              SizedBox(height: 24.w),
              Center(
                child: Container(
                  width: 220.w,
                  height: 220.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surfaceMuted,
                    border: Border.all(
                        color: photo == null ? c.borderStrong : c.success,
                        width: 3),
                    image: photo == null
                        ? null
                        : DecorationImage(
                            image: imageFor(photo)!, fit: BoxFit.cover),
                  ),
                  child: photo == null
                      ? Icon(IconsaxPlusLinear.user,
                          size: 72.w, color: c.textTertiary)
                      : null,
                ),
              ),
              SizedBox(height: 20.w),
              for (final tip in const [
                'Face fills the circle',
                'No glasses, cap or mask',
                'Bright, even light'
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: 6.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(IconsaxPlusLinear.tick_circle,
                          size: 16.w, color: c.success),
                      SizedBox(width: 6.w),
                      Text(tip, style: AppText.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        );
    }
  }
}

class _Result extends StatelessWidget {
  const _Result(
      {required this.icon,
      required this.color,
      required this.title,
      required this.message,
      this.action});

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'ID check',
      bottom: action,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64.w, color: color),
              SizedBox(height: 16.w),
              Text(title, textAlign: TextAlign.center, style: AppText.headline),
              SizedBox(height: 8.w),
              Text(message,
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: context.colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
