import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../data/models/models.dart';
import 'artisan_home_screen.dart';
import 'client_home_screen.dart';

/// The Home tab: clients look for help, artisans run their business.
///
/// Switching sides (a guest's "Find work on RijHub", or signing in as the
/// other role) cross-fades from one home to the other, so the change reads
/// as intended; with reduced motion it is instant.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select<SessionController, UserRole?>((s) => s.role);
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.base),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      child: role == UserRole.artisan
          ? const ArtisanHomeScreen(key: ValueKey(UserRole.artisan))
          : const ClientHomeScreen(key: ValueKey(UserRole.client)),
    );
  }
}
