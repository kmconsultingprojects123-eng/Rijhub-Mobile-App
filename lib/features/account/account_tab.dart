import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../artisan_profile/artisan_profile_screen.dart';
import '../booking/booking_sheets.dart';
import '../bookings/bookings_tab.dart';
import '../shared/page.dart';

/// The Profile tab: who you are, your things, help, and settings.
class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: session.isGuest
            ? const _GuestAccount()
            : session.role == UserRole.artisan
                ? const _ArtisanAccount()
                : const _ClientAccount(),
      ),
    );
  }
}

class _GuestAccount extends StatelessWidget {
  const _GuestAccount();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.read<SessionController>();
    final artisan = session.role == UserRole.artisan;
    return ListView(
      children: [
        const TabTitle('Profile'),
        Padding(
          padding:
              EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
          child: Container(
            padding: EdgeInsets.all(18.w),
            decoration: BoxDecoration(
                color: c.surfaceStrong,
                borderRadius: BorderRadius.circular(22.w)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RijHubAvatar(size: 44),
                SizedBox(height: 14.w),
                Text(
                  artisan ? 'Get jobs near you' : 'Join RijHub',
                  style: AppText.headline.copyWith(color: c.onSurfaceStrong),
                ),
                SizedBox(height: 6.w),
                Text(
                  artisan
                      ? 'Create your free profile to quote on jobs and get booked. It takes about a minute.'
                      : 'Book in minutes, save your favourite artisans, and follow every job. Just your phone number, no password.',
                  style: AppText.body.copyWith(
                      color: c.onSurfaceStrong.withValues(alpha: 0.75)),
                ),
                SizedBox(height: 16.w),
                AppButton(
                  label: artisan
                      ? 'Create your free profile'
                      : 'Sign in or sign up',
                  variant: AppButtonVariant.inverse,
                  onPressed: () => context.read<AuthGate>().ensureSignedIn(
                        context,
                        artisan ? AuthPrompt.joinAsArtisan : AuthPrompt.join,
                      ),
                ),
              ],
            ),
          ),
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: artisan
                  ? IconsaxPlusLinear.search_normal_1
                  : IconsaxPlusLinear.briefcase,
              label:
                  artisan ? 'Looking to hire someone?' : 'Are you an artisan?',
              subtitle: artisan
                  ? 'Switch to finding artisans'
                  : 'Find jobs near you and get paid safely',
              onTap: () async {
                await session.continueAsGuest(
                    artisan ? UserRole.client : UserRole.artisan);
                if (context.mounted) context.go(Routes.home);
              },
            ),
          ],
        ),
        const _HelpAndSettings(),
        const _Version(),
      ],
    );
  }
}

class _ClientAccount extends StatelessWidget {
  const _ClientAccount();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return ListView(
      children: [
        const TabTitle('Profile'),
        _ProfileCard(
          user: user,
          line: NigerianPhone.display(user.phone.replaceFirst('+234', '')),
        ),
        SettingsGroup(
          children: [
            SettingsRow(
                icon: IconsaxPlusLinear.heart,
                label: 'Saved artisans',
                onTap: () => context.push(Routes.saved)),
            SettingsRow(
                icon: IconsaxPlusLinear.location,
                label: 'Places',
                onTap: () => context.push(Routes.places)),
            SettingsRow(
                icon: IconsaxPlusLinear.wallet_2,
                label: 'Payments and receipts',
                onTap: () => context.push(Routes.payments)),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: IconsaxPlusLinear.briefcase,
              label: 'Work as an artisan',
              subtitle: 'Get jobs near you with this account',
              onTap: () => _switchToArtisan(context),
            ),
          ],
        ),
        const _HelpAndSettings(),
        const _SignOutGroup(),
        const _Version(),
      ],
    );
  }

  Future<void> _switchToArtisan(BuildContext context) async {
    final trades = await showTradePicker(context);
    if (trades == null || !context.mounted) return;
    final user = await runAction(
        context,
        () => context
            .read<AccountRepository>()
            .switchRole(UserRole.artisan, tradeIds: trades));
    if (user == null || !context.mounted) return;
    // The new role swaps this tab, taking this row with it.
    final app = appContext(context);
    await context.read<SessionController>().signIn(user);
    if (!app.mounted) return;
    app.go(Routes.home);
    showToast(app, "You're in work mode. Switch back any time from Profile.");
  }
}

/// Picks up to three trades. Null when the person backs out.
Future<List<String>?> showTradePicker(BuildContext context,
    {List<String> initial = const []}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => _TradePicker(initial: initial),
  );
}

class _TradePicker extends StatefulWidget {
  const _TradePicker({required this.initial});

  final List<String> initial;

  @override
  State<_TradePicker> createState() => _TradePickerState();
}

class _TradePickerState extends State<_TradePicker> {
  late final _picked = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("What's your trade?", style: AppText.headline),
            SizedBox(height: 6.w),
            Text('Pick up to 3. Your main one first.',
                style: AppText.body.copyWith(color: c.textSecondary)),
            SizedBox(height: 14.w),
            Wrap(
              spacing: 8.w,
              children: [
                for (final t in Trades.all)
                  PromptChip(
                    label: t.name,
                    selected: _picked.contains(t.id),
                    onTap: () => setState(() {
                      if (_picked.contains(t.id)) {
                        _picked.remove(t.id);
                      } else if (_picked.length < 3) {
                        _picked.add(t.id);
                      }
                    }),
                  ),
              ],
            ),
            SizedBox(height: 18.w),
            AppButton(
              label: _picked.isEmpty ? 'Pick at least one' : 'Continue',
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_picked),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtisanAccount extends StatelessWidget {
  const _ArtisanAccount();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user!;
    return Loader<(ArtisanProfile, Verification, WalletSummary)>(
      reloadOn: session,
      load: () async {
        final r = await Future.wait<Object>([
          context.read<ArtisanSetupRepository>().myProfile(),
          context.read<ArtisanSetupRepository>().verification(),
          context.read<WalletRepository>().summary(),
        ]);
        return (
          r[0] as ArtisanProfile,
          r[1] as Verification,
          r[2] as WalletSummary
        );
      },
      builder: (context, d, reload) {
        final (profile, verification, wallet) = d;
        final (vLabel, vTone) = switch (verification.state) {
          VerificationState.verified => ('Verified', TagTone.success),
          VerificationState.pending => ('Checking', TagTone.info),
          VerificationState.failed => ('Try again', TagTone.warning),
          VerificationState.notStarted => ('Not yet', TagTone.warning),
        };
        return RefreshIndicator(
          color: context.colors.brandStroke,
          onRefresh: reload,
          child: ListView(
            children: [
              const TabTitle('Profile'),
              _ProfileCard(
                user: user,
                line: '${profile.artisan.trade} · ${profile.serviceArea.area}',
                verified: verification.state == VerificationState.verified,
                rating:
                    profile.ratings.count == 0 ? null : profile.ratings.average,
              ),
              // Only while it's still to do: once verified, the badge says it.
              if (verification.state != VerificationState.verified)
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: IconsaxPlusLinear.verify,
                      label: 'Get verified',
                      subtitle: 'Clients can book you once your ID is checked',
                      trailing: StatusTag(label: vLabel, tone: vTone),
                      onTap: () => context.push(Routes.verification),
                    ),
                  ],
                ),
              SettingsGroup(
                children: [
                  SettingsRow(
                      icon: IconsaxPlusLinear.eye,
                      label: 'See your profile as clients do',
                      onTap: () => context.push(Routes.myProfile)),
                  SettingsRow(
                    icon: IconsaxPlusLinear.tag,
                    label: 'Services and prices',
                    value: profile.services.isEmpty
                        ? 'Add'
                        : '${profile.services.length}',
                    onTap: () => context.push(Routes.services),
                  ),
                  SettingsRow(
                    icon: IconsaxPlusLinear.gallery,
                    label: 'Work photos',
                    value:
                        profile.work.isEmpty ? 'Add' : '${profile.work.length}',
                    onTap: () => context.push(Routes.portfolio),
                  ),
                  SettingsRow(
                    icon: IconsaxPlusLinear.location,
                    label: 'Work area',
                    value:
                        '${profile.serviceArea.radiusKm} km of ${profile.serviceArea.area}',
                    onTap: () => context.push(Routes.workArea),
                  ),
                  SettingsRow(
                      icon: IconsaxPlusLinear.clock,
                      label: 'Working hours',
                      value: hoursLabel(profile.hours),
                      onTap: () => context.push(Routes.hours)),
                  SettingsRow(
                    icon: IconsaxPlusLinear.star_1,
                    label: 'Reviews',
                    value: profile.ratings.count == 0
                        ? 'None yet'
                        : '${profile.ratings.average.toStringAsFixed(1)} · ${profile.ratings.count}',
                    onTap: () => context.push(Routes.reviews),
                  ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: IconsaxPlusLinear.wallet_2,
                    label: 'Wallet and payouts',
                    value: Naira.format(wallet.available),
                    onTap: () => context.push(Routes.wallet),
                  ),
                  SettingsRow(
                    icon: IconsaxPlusLinear.search_normal_1,
                    label: 'Hire for yourself',
                    subtitle: 'Switch to finding artisans',
                    onTap: () async {
                      final user = await runAction(
                          context,
                          () => context
                              .read<AccountRepository>()
                              .switchRole(UserRole.client));
                      if (user == null || !context.mounted) return;
                      final app = appContext(context);
                      await context.read<SessionController>().signIn(user);
                      if (!app.mounted) return;
                      app.go(Routes.home);
                      showToast(app,
                          "You're hiring now. Switch back any time from Profile.");
                    },
                  ),
                ],
              ),
              const _HelpAndSettings(),
              const _SignOutGroup(),
              const _Version(),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.user,
      required this.line,
      this.verified = false,
      this.rating});

  final AppUser user;
  final String line;
  final bool verified;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
      child: Column(
        children: [
          Row(
            children: [
              AppAvatar(
                  name: user.fullName, image: imageFor(user.photo), size: 64.w),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                            child: Text(user.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.title)),
                        if (verified) ...[
                          SizedBox(width: 6.w),
                          const VerifiedBadge(size: 17)
                        ],
                      ],
                    ),
                    SizedBox(height: 2.w),
                    Text(line,
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary)),
                    if (rating != null) ...[
                      SizedBox(height: 4.w),
                      RatingLabel(rating: rating!)
                    ],
                  ],
                ),
              ),
              AppButton(
                label: 'Edit',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: () => context.push(Routes.editProfile),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpAndSettings extends StatelessWidget {
  const _HelpAndSettings();

  @override
  Widget build(BuildContext context) => SettingsGroup(
        children: [
          SettingsRow(
            icon: IconsaxPlusLinear.message_question,
            label: 'Help and support',
            subtitle: 'Answers, chat or a call',
            onTap: () => context.push(Routes.support),
          ),
          SettingsRow(
              icon: IconsaxPlusLinear.setting_2,
              label: 'Settings',
              onTap: () => context.push(Routes.settings)),
        ],
      );
}

class _SignOutGroup extends StatelessWidget {
  const _SignOutGroup();

  @override
  Widget build(BuildContext context) => SettingsGroup(
        children: [
          SettingsRow(
            icon: IconsaxPlusLinear.logout,
            label: 'Sign out',
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'Sign out?',
                message:
                    'You can keep looking around as a guest. Sign back in any time with your phone number.',
                confirm: 'Sign out',
              );
              if (ok && context.mounted) {
                // Signing out swaps this tab for the guest one, taking this
                // row with it.
                final app = appContext(context);
                await context.read<SessionController>().signOut();
                if (app.mounted) app.go(Routes.home);
              }
            },
          ),
        ],
      );
}

class _Version extends StatelessWidget {
  const _Version();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 28.w),
        child: Center(
          child: Text('RijHub 2.0.0 · Made in Abuja',
              style:
                  AppText.caption.copyWith(color: context.colors.textTertiary)),
        ),
      );
}
