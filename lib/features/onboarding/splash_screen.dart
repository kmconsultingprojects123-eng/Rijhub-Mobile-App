import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';

/// Carries on from the native launch screen. On iOS and Android before 12
/// that shows this same white wordmark, at the same size on the same
/// crimson, so the hand-off can't be seen. The session is already restored,
/// so there is nothing to wait for beyond a short brand moment.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.hold = false});

  /// Debug only: stay on this screen (for screenshots).
  final bool hold;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.hold) return;
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      // The first open starts with the welcome conversation.
      final onboarded = context.read<SessionController>().hasOnboarded;
      context.go(onboarded ? Routes.home : Routes.welcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.brand,
        body: const Center(
          // The launch images are 196 x 64 on every phone, so this isn't
          // scaled with the screen, and it starts fully drawn.
          child: RijHubLogo(variant: LogoVariant.white, height: 64),
        ),
      ),
    );
  }
}
