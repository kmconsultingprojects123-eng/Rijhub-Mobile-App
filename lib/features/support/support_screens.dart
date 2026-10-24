import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../shared/page.dart';

const supportPhone = '08053466666';
const supportEmail = 'support@rijhub.com';

/// Answers first, then the ways to reach a person.
class HelpCentreScreen extends StatefulWidget {
  const HelpCentreScreen({super.key});

  @override
  State<HelpCentreScreen> createState() => _HelpCentreScreenState();
}

class _HelpCentreScreenState extends State<HelpCentreScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chat() async {
    final ok = await context.read<AuthGate>().ensureSignedIn(
          context,
          const AuthPrompt(
              title: 'Chat with us',
              message:
                  'Add your phone number so we can follow up on your question.'),
        );
    if (!ok || !mounted) return;
    final convo = await context.read<ChatRepository>().withSupport();
    if (mounted) context.push(Routes.chat(convo.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    return PageScaffold(
      title: 'Help centre',
      body: Loader<List<FaqItem>>(
        load: () => context.read<SupportRepository>().faqs(),
        builder: (context, faqs, _) {
          final q = _search.text.trim().toLowerCase();
          final shown = q.isEmpty
              ? faqs
              : faqs
                  .where((f) =>
                      f.question.toLowerCase().contains(q) ||
                      f.answer.toLowerCase().contains(q))
                  .toList();
          final topics = <String, List<FaqItem>>{};
          for (final f in shown) {
            (topics[f.topic] ??= []).add(f);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(0, 4.w, 0, 28.w),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: g),
                child: Container(
                  height: 52.w,
                  padding: EdgeInsets.only(left: 16.w, right: 8.w),
                  decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(color: c.border)),
                  child: Row(
                    children: [
                      Icon(IconsaxPlusLinear.search_normal_1,
                          size: 20.w, color: c.textSecondary),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: AppText.body,
                          cursorColor: c.brandStroke,
                          decoration: InputDecoration(
                            hintText: 'Search for an answer',
                            hintStyle:
                                AppText.body.copyWith(color: c.textTertiary),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.w),
              if (q.isEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: g),
                  child: LiveBar(
                    leading: const RijHubAvatar(size: 40),
                    title: 'Talk to Employi',
                    subtitle: 'Voice help, any time of day',
                    actionLabel: 'Call',
                    onTap: () => context.push(Routes.voiceSupport),
                  ),
                ),
                SizedBox(height: 16.w),
                SettingsGroup(
                  title: 'Reach our team',
                  children: [
                    SettingsRow(
                        icon: IconsaxPlusLinear.messages_2,
                        label: 'Chat with us',
                        subtitle: 'Usually replies in 10 minutes',
                        onTap: _chat),
                    SettingsRow(
                      icon: IconsaxPlusLinear.call,
                      label: 'Call us',
                      value: '0805 346 6666',
                      onTap: () =>
                          launchUrl(Uri(scheme: 'tel', path: supportPhone)),
                    ),
                    SettingsRow(
                      icon: FontAwesomeIcons.whatsapp,
                      label: 'WhatsApp',
                      onTap: () => launchUrl(
                          Uri.parse(
                              'https://wa.me/234${supportPhone.substring(1)}'),
                          mode: LaunchMode.externalApplication),
                    ),
                    SettingsRow(
                      icon: IconsaxPlusLinear.sms,
                      label: 'Email',
                      value: supportEmail,
                      onTap: () => launchUrl(Uri(
                          scheme: 'mailto',
                          path: supportEmail,
                          query: 'subject=Help with Employi')),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(g, 0, g, 20.w),
                  child: Text(
                    'Our team is in Monday to Friday 9 AM–6 PM and Saturday 10 AM–4 PM. Talk to Employi any time.',
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
              for (final entry in topics.entries)
                SettingsGroup(
                  title: entry.key,
                  children: [
                    for (final f in entry.value)
                      SettingsRow(
                          icon: IconsaxPlusLinear.message_question,
                          label: f.question,
                          onTap: () => context.push(Routes.faq(f.id))),
                  ],
                ),
              if (shown.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: g, vertical: 40.w),
                  child: EmptyState(
                    icon: IconsaxPlusLinear.message_question,
                    title: 'No answer for that yet',
                    message: 'Chat with us and we\'ll help.',
                    action: AppButton(
                        label: 'Chat with us', expand: false, onPressed: _chat),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key, required this.faqId});

  final String faqId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: 'Help',
      body: Loader<List<FaqItem>>(
        load: () => context.read<SupportRepository>().faqs(),
        builder: (context, faqs, _) {
          final f =
              faqs.firstWhere((x) => x.id == faqId, orElse: () => faqs.first);
          final related = faqs
              .where((x) => x.topic == f.topic && x.id != f.id)
              .take(3)
              .toList();
          return ListView(
            padding: EdgeInsets.fromLTRB(
                AppSpace.gutter, 8.w, AppSpace.gutter, 28.w),
            children: [
              Text(f.topic,
                  style: AppText.labelSmall.copyWith(color: c.brandText)),
              SizedBox(height: 6.w),
              Text(f.question, style: AppText.headline),
              SizedBox(height: 12.w),
              Text(f.answer, style: AppText.bodyLarge),
              SizedBox(height: 24.w),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(16.w)),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('Still stuck?', style: AppText.titleSmall)),
                    AppButton(
                      label: 'Get help',
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed: () => goBack(context),
                    ),
                  ],
                ),
              ),
              if (related.isNotEmpty) ...[
                SizedBox(height: 24.w),
                Text('Related', style: AppText.title),
                for (final r in related)
                  SettingsRow(
                      icon: IconsaxPlusLinear.message_question,
                      label: r.question,
                      onTap: () => context.pushReplacement(Routes.faq(r.id))),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A voice call with RijHub's assistant: speak, and it answers.
///
/// The call goes through RijHub's backend (so no AI keys live in the app);
/// until that exists, the screen shows the call without audio.
class VoiceSupportScreen extends StatefulWidget {
  const VoiceSupportScreen({super.key});

  @override
  State<VoiceSupportScreen> createState() => _VoiceSupportScreenState();
}

enum _CallState { connecting, listening, speaking, ended }

class _VoiceSupportScreenState extends State<VoiceSupportScreen>
    with SingleTickerProviderStateMixin {
  _CallState _state = _CallState.connecting;
  bool _muted = false;
  bool _speaker = true;
  final _started = DateTime.now();
  late final Timer _tick;
  Timer? _connect;
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  static const _limit = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().difference(_started) >= _limit) _end();
      setState(() {});
    });
    _connect = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _state = _CallState.speaking);
      _connect = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _state = _CallState.listening);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _tick.cancel();
    _connect?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _end() {
    setState(() => _state = _CallState.ended);
    _connect?.cancel();
    Timer(const Duration(milliseconds: 700), () {
      if (mounted) goBack(context);
    });
  }

  Future<void> _person() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Talk to a person', style: AppText.headline),
              SizedBox(height: 6.w),
              Text(
                  'Our team is in Monday to Friday 9 AM–6 PM, Saturday 10 AM–4 PM.',
                  style: AppText.body
                      .copyWith(color: context.colors.textSecondary)),
              SizedBox(height: 16.w),
              SelectionCard(
                  icon: IconsaxPlusLinear.call,
                  title: 'Call support',
                  subtitle: '0805 346 6666',
                  selected: false,
                  onTap: () => Navigator.of(context).pop('call')),
              SizedBox(height: 8.w),
              SelectionCard(
                  icon: IconsaxPlusLinear.sms,
                  title: 'Email us',
                  subtitle: supportEmail,
                  selected: false,
                  onTap: () => Navigator.of(context).pop('email')),
              SizedBox(height: 8.w),
              AppButton(
                  label: 'Stay with Employi',
                  variant: AppButtonVariant.tertiary,
                  onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
    if (choice == 'call') {
      await launchUrl(Uri(scheme: 'tel', path: supportPhone));
    } else if (choice == 'email') {
      await launchUrl(Uri(scheme: 'mailto', path: supportEmail));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final elapsed = DateTime.now().difference(_started);
    final left = _limit - elapsed;
    final status = switch (_state) {
      _CallState.connecting => 'Connecting…',
      _CallState.speaking => 'Employi is speaking',
      _CallState.listening =>
        _muted ? 'You are muted' : 'Listening. Go ahead and speak',
      _CallState.ended => 'Call ended',
    };
    const dark = Color(0xFF111113);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: dark,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppIconButton(
                  icon: IconsaxPlusLinear.arrow_down,
                  iconColor: Colors.white,
                  semanticLabel: 'Minimise',
                  onPressed: () => goBack(context),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220.w,
                height: 220.w,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 100.w + 120.w * ((_pulse.value + i / 3) % 1),
                          height: 100.w + 120.w * ((_pulse.value + i / 3) % 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.brand.withValues(
                              alpha: _state == _CallState.ended
                                  ? 0
                                  : 0.28 *
                                      (1 - ((_pulse.value + i / 3) % 1)) *
                                      (_state == _CallState.speaking
                                          ? 1.4
                                          : 0.8),
                            ),
                          ),
                        ),
                      child!,
                    ],
                  ),
                  child: const RijHubAvatar(size: 100),
                ),
              ),
              SizedBox(height: 24.w),
              Text('Employi',
                  style: AppText.headline.copyWith(color: Colors.white)),
              SizedBox(height: 6.w),
              Semantics(
                liveRegion: true,
                child: Text(status,
                    style: AppText.body
                        .copyWith(color: Colors.white.withValues(alpha: 0.7))),
              ),
              SizedBox(height: 4.w),
              Text(
                '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                style: AppText.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (left < const Duration(minutes: 1))
                Padding(
                  padding: EdgeInsets.only(top: 8.w),
                  child: Text(
                      'Calls end after 15 minutes. Less than a minute left.',
                      style:
                          AppText.caption.copyWith(color: c.warningOnStrong)),
                ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.s32),
                child: Text(
                  'Ask about a booking, a payment or how anything works. Say "talk to a person" any time.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall
                      .copyWith(color: Colors.white.withValues(alpha: 0.55)),
                ),
              ),
              SizedBox(height: 24.w),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: _muted
                        ? IconsaxPlusBold.microphone_slash
                        : IconsaxPlusLinear.microphone_2,
                    label: _muted ? 'Unmute' : 'Mute',
                    on: _muted,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  _CallButton(
                    icon: IconsaxPlusLinear.call_remove,
                    label: 'End',
                    end: true,
                    onTap: _state == _CallState.ended ? null : _end,
                  ),
                  _CallButton(
                    icon: _speaker
                        ? IconsaxPlusBold.volume_high
                        : IconsaxPlusLinear.volume_low_1,
                    label: 'Speaker',
                    on: _speaker,
                    onTap: () => setState(() => _speaker = !_speaker),
                  ),
                ],
              ),
              SizedBox(height: 16.w),
              Semantics(
                button: true,
                child: InkWell(
                  onTap: _person,
                  borderRadius: AppRadius.pillAll,
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.w),
                    child: Text('Talk to a person',
                        style: AppText.label.copyWith(color: Colors.white)),
                  ),
                ),
              ),
              SizedBox(height: 12.w),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.on = false,
      this.end = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool on;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: end ? null : on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 68.w,
              height: 68.w,
              decoration: BoxDecoration(
                color: end
                    ? c.error
                    : (on
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.12)),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 28.w,
                  color: end
                      ? Colors.white
                      : (on ? const Color(0xFF111113) : Colors.white)),
            ),
            SizedBox(height: 8.w),
            Text(label,
                style: AppText.caption
                    .copyWith(color: Colors.white.withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }
}

/// Terms of use or the privacy policy.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.privacy});

  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sections = privacy ? _privacy : _terms;
    return PageScaffold(
      title: privacy ? 'Privacy policy' : 'Terms of use',
      subtitle: 'Last updated October 2026',
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 8.w, AppSpace.gutter, 32.w),
        children: [
          Text(
            privacy
                ? 'How Employi collects, uses and protects your information, in plain words.'
                : 'The rules for using Employi, in plain words. By using Employi you agree to them.',
            style: AppText.bodyLarge.copyWith(color: c.textSecondary),
          ),
          for (final (i, (title, body)) in sections.indexed) ...[
            SizedBox(height: 22.w),
            Text('${i + 1}. $title', style: AppText.title),
            SizedBox(height: 6.w),
            Text(body, style: AppText.body),
          ],
          SizedBox(height: 28.w),
          AppButton(
            label:
                privacy ? 'Read the terms of use' : 'Read the privacy policy',
            variant: AppButtonVariant.secondary,
            onPressed: () => context
                .pushReplacement(privacy ? Routes.terms : Routes.privacy),
          ),
          SizedBox(height: 10.w),
          Text(
            'Questions? Email $supportEmail.',
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  static const _terms = [
    (
      'What Employi is',
      'Employi, powered by RijHub, is a marketplace that connects clients with independent artisans in Abuja. Artisans don\'t work for Employi; they set their own prices and do the work. Employi provides the app, checks identities, holds payments and helps when things go wrong.'
    ),
    (
      'Your account',
      'You must be 18 or older. Sign in with a phone number you own, keep your details accurate, and don\'t share your account. One account can be used as a client and as an artisan.'
    ),
    (
      'Booking and paying',
      'When you book, you pay the price shown plus a service fee. Employi holds the money and releases it to the artisan when you confirm the job is done. If you don\'t confirm or raise a problem within 48 hours of the artisan marking it done, the payment is released automatically.'
    ),
    (
      'Fees and fair dealing',
      'Clients pay a service fee shown before they book. Artisans and clients must not arrange to pay outside Employi for work found on Employi; doing so removes payment protection and can close the account.'
    ),
    (
      'Cancellations and refunds',
      'You can cancel before the artisan sets off for a full refund. If the artisan doesn\'t show up, you get a full refund. If you cancel after the artisan has arrived, a call-out fee may apply. Disputes are reviewed by our team, who can refund in full or in part.'
    ),
    (
      'Reviews',
      'Reviews must be honest and about real bookings. We remove reviews that are abusive, fake, or include personal information.'
    ),
    (
      'Artisans',
      'Artisans must hold the skills they list, complete the ID check before taking bookings, quote honestly, turn up as agreed, and follow safety rules for their trade.'
    ),
    (
      'Our responsibility',
      'We work hard to keep Employi safe and reliable, but the artisan is responsible for their work. Our liability is limited to the fees you paid us for the booking in question, except where the law says otherwise.'
    ),
    (
      'Changes and contact',
      'We may update these terms and will tell you about important changes in the app. Contact us at support@rijhub.com.'
    ),
  ];

  static const _privacy = [
    (
      'What we collect',
      'Your name, phone number, email if you add one, your area and the addresses you book at, your bookings, messages, photos and voice notes you send, and payment references (not your card details, which our payment partner handles). For artisans, also your NIN and selfie for the ID check, and your bank account for payouts.'
    ),
    (
      'How we use it',
      'To match you with artisans or jobs, run bookings and payments, keep Employi safe, give support, and improve the app. We use your area, not your exact location, unless you share it for a booking.'
    ),
    (
      'Who we share it with',
      'With the other side of a booking, only what they need (for example, your first name, area and the address once the booking is confirmed). With service providers who help us run Employi, such as payment and ID-check partners, under contract. With authorities when the law requires.'
    ),
    (
      'Calls and numbers',
      'Calls about a booking go through an Employi number, so neither side sees the other\'s own number.'
    ),
    (
      'How long we keep it',
      'As long as your account is open, then only what the law requires us to keep, such as payment records.'
    ),
    (
      'Your choices and rights',
      'You can see and change your details in the app, choose which notifications you get, and delete your account at any time. You can ask us for a copy of your data or to correct it.'
    ),
    (
      'Security',
      'Your data is encrypted in transit, payments are handled by a licensed payment partner, and access inside Employi is limited to people who need it.'
    ),
  ];
}
