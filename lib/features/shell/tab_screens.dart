import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

// The tabs beside Home. Guests see a clear reason to sign in where an
// account is needed; screens not yet rebuilt say so plainly.

class ExploreTab extends StatelessWidget {
  const ExploreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isArtisan = context.select<SessionController, bool>(
      (s) => s.role == UserRole.artisan,
    );
    return isArtisan
        ? const _ComingSoon(
            title: 'Jobs',
            icon: IconsaxPlusLinear.briefcase,
            message: 'Browse every open job near you and send quotes.',
          )
        : const _ComingSoon(
            title: 'Explore',
            icon: IconsaxPlusLinear.search_normal_1,
            message: 'Search every service and see artisans on a map.',
          );
  }
}

class BookingsTab extends StatelessWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final isArtisan = session.role == UserRole.artisan;
    final title = isArtisan ? 'Schedule' : 'Bookings';
    if (session.isGuest) {
      return _SignInGate(
        title: title,
        icon: IconsaxPlusLinear.calendar_tick,
        heading:
            isArtisan ? 'Your schedule lives here' : 'Your bookings live here',
        message: isArtisan
            ? 'Get booked by clients and see your week at a glance.'
            : 'Sign in to book artisans and follow every job, from quote to payment.',
        isArtisan: isArtisan,
        prompt: isArtisan ? AuthPrompt.joinAsArtisan : AuthPrompt.bookings,
      );
    }
    return _ComingSoon(
      title: title,
      icon: IconsaxPlusLinear.calendar_tick,
      message: isArtisan
          ? 'Your upcoming jobs, day by day.'
          : 'Track every booking, from quote to payment.',
    );
  }
}

class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (session.isGuest) {
      final isArtisan = session.role == UserRole.artisan;
      return _SignInGate(
        title: 'Messages',
        icon: IconsaxPlusLinear.message,
        heading: isArtisan ? 'Talk to clients' : 'Talk to artisans',
        message: isArtisan
            ? 'Chat with clients before and after you do the job.'
            : 'Sign in to chat with artisans before and after they do the job.',
        isArtisan: isArtisan,
        prompt: isArtisan ? AuthPrompt.joinAsArtisan : AuthPrompt.messages,
      );
    }
    return const _ComingSoon(
      title: 'Messages',
      icon: IconsaxPlusLinear.message,
      message: 'Chat with artisans and clients about each job.',
    );
  }
}

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.watch<SessionController>();
    final user = session.user;
    final isArtisan = session.role == UserRole.artisan;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpace.gutter,
            vertical: AppSpace.s24,
          ),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Profile',
                style: AppText.headline.copyWith(color: c.textPrimary),
              ),
            ),
            SizedBox(height: AppSpace.s24),
            if (user == null)
              _JoinCard(isArtisan: isArtisan)
            else
              AppCard(
                child: Row(
                  children: [
                    // The name is beside it, so the photo stays silent.
                    ExcludeSemantics(
                      child: AppAvatar(
                        name: user.fullName,
                        image: imageFor(user.photo),
                        size: AppSpace.s48 + AppSpace.s8,
                      ),
                    ),
                    SizedBox(width: AppSpace.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: AppText.titleSmall
                                .copyWith(color: c.textPrimary),
                          ),
                          SizedBox(height: AppSpace.s2),
                          Text(
                            NigerianPhone.display(
                              NigerianPhone.normalize(user.phone),
                            ),
                            style: AppText.bodySmall
                                .copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    StatusTag(
                      label:
                          user.role == UserRole.artisan ? 'Artisan' : 'Client',
                      tone: TagTone.brand,
                    ),
                  ],
                ),
              ),
            SizedBox(height: AppSpace.s16),
            if (user == null)
              _RoleSwitch(isArtisan: isArtisan)
            else ...[
              Text(
                'Settings, payments and support are next in the redesign.',
                style: AppText.bodySmall.copyWith(color: c.textTertiary),
              ),
              SizedBox(height: AppSpace.s32),
              AppButton(
                label: 'Sign out',
                variant: AppButtonVariant.secondary,
                leading: Icon(IconsaxPlusLinear.logout, size: AppSize.icon),
                onPressed: session.signOut,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The guest's way in from the Profile tab.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.isArtisan});

  final bool isArtisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gate = context.read<AuthGate>();
    // Each line is its own stop, so the title reads first, as a heading.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: AppCard(
        padding: EdgeInsets.all(AppSpace.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                isArtisan ? 'Start getting jobs' : 'Join RijHub',
                style: AppText.title.copyWith(color: c.textPrimary),
              ),
            ),
            SizedBox(height: AppSpace.s6),
            Text(
              isArtisan
                  ? 'All you need is your phone number, name and trade.'
                  : 'Book trusted artisans and keep every job in one place. All you need is your phone number.',
              style: AppText.body.copyWith(color: c.textSecondary),
            ),
            SizedBox(height: AppSpace.s20),
            AppButton(
              label:
                  isArtisan ? 'Create your free profile' : 'Sign in or sign up',
              onPressed: () => gate.ensureSignedIn(
                context,
                // Guests here are mostly new, so not "Welcome back".
                isArtisan ? AuthPrompt.joinAsArtisan : AuthPrompt.join,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets a guest move between the client and artisan sides.
class _RoleSwitch extends StatelessWidget {
  const _RoleSwitch({required this.isArtisan});

  final bool isArtisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label =
        isArtisan ? 'Need an artisan instead?' : 'Are you an artisan?';
    final action = isArtisan ? 'Hire an artisan' : 'Find work on RijHub';
    return AppCard(
      onTap: () => context.read<SessionController>().continueAsGuest(
            isArtisan ? UserRole.client : UserRole.artisan,
          ),
      semanticLabel: '$label $action',
      child: Row(
        children: [
          Container(
            width: AppSpace.s40,
            height: AppSpace.s40,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(
              isArtisan
                  ? IconsaxPlusLinear.user_search
                  : IconsaxPlusLinear.briefcase,
              size: AppSize.icon,
              color: c.textPrimary,
            ),
          ),
          SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary)),
                Text(action,
                    style: AppText.titleSmall.copyWith(color: c.textPrimary)),
              ],
            ),
          ),
          Icon(IconsaxPlusLinear.arrow_right_3,
              size: AppSize.icon, color: c.textTertiary),
        ],
      ),
    );
  }
}

/// A tab that needs an account, shown to guests.
class _SignInGate extends StatelessWidget {
  const _SignInGate({
    required this.title,
    required this.icon,
    required this.heading,
    required this.message,
    required this.isArtisan,
    required this.prompt,
  });

  final String title;
  final IconData icon;
  final String heading;
  final String message;

  /// Artisans are invited as the artisan home invites them: to create a
  /// profile, which takes about a minute.
  final bool isArtisan;
  final AuthPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _TabScaffold(
      title: title,
      child: EmptyState(
        icon: icon,
        title: heading,
        message: message,
        action: Column(
          children: [
            AppButton(
              label:
                  isArtisan ? 'Create your free profile' : 'Sign in or sign up',
              size: AppButtonSize.medium,
              onPressed: () =>
                  context.read<AuthGate>().ensureSignedIn(context, prompt),
            ),
            SizedBox(height: AppSpace.s12),
            Text(
              isArtisan
                  ? 'It takes about a minute.'
                  : 'New here? It takes under a minute.',
              style: AppText.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => _TabScaffold(
        title: title,
        child: EmptyState(
          icon: icon,
          title: 'Coming in the redesign',
          message: message,
        ),
      );
}

class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s24,
            AppSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppText.headline.copyWith(color: c.textPrimary),
                ),
              ),
              Expanded(child: Center(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}
