import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

/// How a first-time visitor leaves the welcome sheet.
enum WelcomeChoice { explore, findWork, signIn }

/// Welcomes a first-time visitor over the real home, which is already
/// loaded and visible behind a light scrim, so "look around first" is
/// something they can see, not just read.
///
/// Exploring is the default: the main button, a swipe down and a tap on
/// the dimmed home all let the person in as a guest client. Artisans have
/// the second button; returning people sign in from the corner.
Future<void> showWelcomeSheet(BuildContext context) async {
  final session = context.read<SessionController>();
  final gate = context.read<AuthGate>();
  final choice = await showModalBottomSheet<WelcomeChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(
      alpha: context.isDarkMode ? 0.6 : 0.4,
    ),
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => const DoubleTapGuard(child: WelcomeSheet()),
  );
  // Signed in another way while it was open (a link, a QA launch).
  if (session.hasOnboarded) return;
  switch (choice) {
    case WelcomeChoice.findWork:
      await session.continueAsGuest(UserRole.artisan);
    case WelcomeChoice.signIn:
      // Nobody has picked a side yet, so a new number is asked how it will
      // be used. Closing the sign-in sheet carries on exploring.
      if (context.mounted) {
        await gate.ensureSignedIn(context, AuthPrompt.signIn);
      }
      if (!session.hasOnboarded) {
        await session.continueAsGuest(UserRole.client);
      }
    case WelcomeChoice.explore || null:
      await session.continueAsGuest(UserRole.client);
  }
}

/// The welcome's content: what RijHub promises, and the two doors in. It
/// closes by itself if the person gets in some other way while it is open.
class WelcomeSheet extends StatefulWidget {
  const WelcomeSheet({super.key});

  @override
  State<WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends State<WelcomeSheet> {
  late final SessionController _session = context.read<SessionController>();

  /// Set once the sheet is on its way out, so it only ever closes once.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (_closing || !_session.hasOnboarded || !mounted) return;
    _closing = true;
    // Removes this sheet even if another sheet is above it.
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _choose(WelcomeChoice choice) {
    if (_closing) return;
    _closing = true;
    HapticFeedback.selectionClick();
    Navigator.pop(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RijHubLogo(
                  height: 24.w,
                  variant: context.isDarkMode
                      ? LogoVariant.onDark
                      : LogoVariant.color,
                ),
                const Spacer(),
                _SignInLink(onTap: () => _choose(WelcomeChoice.signIn)),
              ],
            ),
            SizedBox(height: AppSpace.s12),
            Semantics(
              header: true,
              child: Text(
                "Abuja's verified artisans, one\u00A0tap\u00A0away",
                style: AppText.headline.copyWith(color: c.textPrimary),
              ),
            ),
            SizedBox(height: AppSpace.s8),
            Text(
              "Look around first. You'll only need your phone number when "
              'you\u00A0book.',
              style: AppText.body.copyWith(color: c.textSecondary),
            ),
            SizedBox(height: AppSpace.s12),
            Wrap(
              spacing: AppSpace.s16,
              runSpacing: AppSpace.s6,
              children: [
                _Promise(
                  icon: IconsaxPlusBold.verify,
                  color: c.verified,
                  label: 'ID-checked artisans',
                ),
                _Promise(
                  icon: IconsaxPlusBold.shield_tick,
                  color: c.success,
                  label: 'Payment held until the job is done',
                ),
              ],
            ),
            SizedBox(height: AppSpace.s24),
            AppButton(
              label: 'Explore as a guest',
              trailing: Icon(IconsaxPlusLinear.arrow_right, size: AppSize.icon),
              onPressed: () => _choose(WelcomeChoice.explore),
            ),
            SizedBox(height: AppSpace.s12),
            AppButton(
              label: 'Find work as an artisan',
              variant: AppButtonVariant.secondary,
              leading: Icon(IconsaxPlusLinear.briefcase, size: AppSize.icon),
              onPressed: () => _choose(WelcomeChoice.findWork),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of RijHub's two promises, with its icon.
class _Promise extends StatelessWidget {
  const _Promise({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSize.iconSmall, color: color),
        SizedBox(width: AppSpace.s6),
        Flexible(
          child: Text(
            label,
            style: AppText.bodySmall.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Sign in", small and in the corner: there for returning people without
/// competing with exploring.
class _SignInLink extends StatelessWidget {
  const _SignInLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Sign in',
      focusRadius: AppRadius.pillAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSize.minTapTarget,
          minWidth: AppSize.minTapTarget,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
          child: Center(
            widthFactor: 1,
            child: Text(
              'Sign in',
              style: AppText.labelSmall.copyWith(color: c.brandText),
            ),
          ),
        ),
      ),
    );
  }
}
