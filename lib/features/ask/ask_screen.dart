import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/media.dart';
import '../../app/push.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/speech.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../booking/checkout.dart';
import '../location/area_picker_sheet.dart';
import '../shared/page.dart';
import 'ask_cards.dart';
import 'ask_flow.dart';
import 'ask_launch.dart';

/// The Ask conversation with RijHub.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, this.launch = const AskLaunch()});

  final AskLaunch launch;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  late final AskFlow _flow;
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final _terms = TapGestureRecognizer()
    ..onTap = () => context.push(Routes.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => context.push(Routes.privacy);
  int _seen = 0;
  double _keyboard = 0;

  // Voice note playback.
  Object? _playing;
  double _progress = 0;
  StreamSubscription<double>? _play;

  @override
  void initState() {
    super.initState();
    _flow = AskFlow(
      session: context.read<SessionController>(),
      authFlow: context.read<AuthFlowController>(),
      ask: context.read<AskRepository>(),
      artisans: context.read<ArtisanRepository>(),
      bookingFlow: context.read<BookingFlowRepository>(),
      clientJobs: context.read<ClientJobRepository>(),
      account: context.read<AccountRepository>(),
      directory: context.read<DirectoryRepository>(),
      media: context.read<MediaService>(),
      jobs: context.read<JobRepository>(),
      catalog: context.read<CatalogRepository>(),
      push: context.read<PushPermission>(),
      speaker: context.read<Speaker>(),
      onPay: (total, description) =>
          showCheckout(context, total: total, description: description),
      onPickDay: () => showDayPicker(context),
      onPickArea: () => showAreaPicker(context),
      onOpen: _open,
    )..addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    final launch = widget.launch;
    if (launch.start == AskStart.welcome) {
      await _flow.startWelcome();
      return;
    }
    Artisan? artisan;
    if (launch.artisanId != null) {
      final profile =
          await context.read<DirectoryRepository>().profile(launch.artisanId!);
      artisan = profile.artisan;
    }
    // Read aloud, unless they came to type: the Ask bar's text box, or a
    // search they typed.
    final talk = artisan != null ||
        launch.start != AskStart.typing ||
        (launch.text != null && !launch.typed);
    await _flow.start(text: launch.text, artisan: artisan, talk: talk);
    if (!mounted) return;
    if (kDebugMode && launch.script.isNotEmpty) {
      await _playScript(launch.script);
      return;
    }
    switch (launch.start) {
      case AskStart.camera:
        await _flow.sendPhoto(camera: true);
      case AskStart.voice:
        await _flow.startVoice();
      case AskStart.typing:
        if (launch.text == null && artisan == null) _focus.requestFocus();
      case AskStart.welcome:
        break;
    }
  }

  /// Debug only: plays [steps] through the conversation, for store
  /// screenshots. Each step taps the reply that names it or, while the input
  /// waits for an address, is sent as typed.
  Future<void> _playScript(List<String> steps) async {
    for (final step in steps) {
      for (var tries = 0; tries < 80 && mounted; tries++) {
        final reply =
            _flow.replies.where((r) => r.label.contains(step)).firstOrNull;
        if (reply != null) {
          reply.onTap();
          break;
        }
        if (_flow.mode == ComposerMode.address) {
          await _flow.sendText(step);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  Future<void> _addService(AskFlow flow) async {
    final others = await flow.otherServices();
    if (!mounted) return;
    final name =
        flow.items.whereType<BotSummary>().last.draft.artisan.firstName;
    if (others.isEmpty) {
      showToast(context, '$name has no other services listed.');
      return;
    }
    final pick = await showChoiceSheet<ServiceOffer>(
      context,
      title: 'Add from $name\'s services',
      options: [
        for (final s in others)
          (
            s,
            '${s.name} · ${s.priceMax == null ? Naira.format(s.price) : Naira.range(s.price, s.priceMax)}'
          ),
      ],
    );
    if (pick != null) await flow.addService(pick);
  }

  void _open(String path) {
    const tabs = [
      Routes.home,
      Routes.explore,
      Routes.bookings,
      Routes.messages,
      Routes.account
    ];
    if (tabs.any(path.startsWith)) {
      context.go(path);
    } else {
      context.push(path);
    }
  }

  void _changed() {
    if (!mounted) return;
    // Reading the newest when it changed: the input below may grow (the
    // number, the code), so it's kept in view.
    final atEnd = _scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
    setState(() {});
    if (_flow.items.length != _seen) {
      _seen = _flow.items.length;
      _toEnd();
    } else if (atEnd) {
      _toEnd(animate: false);
    }
  }

  /// Scrolls to the newest message, once the next frame is laid out.
  void _toEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end,
            duration: context.motion(AppMotion.slow),
            curve: AppMotion.standard);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  void _togglePlay(Object key, VoiceNote note) {
    final media = context.read<MediaService>();
    _play?.cancel();
    if (_playing == key) {
      media.stopPlaying();
      setState(() => _playing = null);
      return;
    }
    setState(() {
      _playing = key;
      _progress = 0;
    });
    _play = media.play(note).listen(
      (p) => setState(() => _progress = p),
      onDone: () {
        if (mounted) setState(() => _playing = null);
      },
    );
  }

  @override
  void dispose() {
    _play?.cancel();
    _flow
      ..removeListener(_changed)
      ..dispose();
    _scroll.dispose();
    _focus.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final flow = _flow;
    // The keyboard opening leaves less room: the question it answers stays
    // in view.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > _keyboard) _toEnd(animate: false);
    _keyboard = keyboard;
    final lastSummary = flow.items.lastIndexWhere((i) => i is BotSummary);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // The welcome is the first screen there is: no way back until
            // the person picks a way in, then back leads home.
            _AskHeader(
              welcome: flow.welcome,
              talking: flow.talking,
              onTalk: flow.toggleTalking,
            ),
            Divider(height: 1, thickness: 1, color: c.border),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(g, 16.w, g, 12.w),
                  itemCount: flow.items.length,
                  itemBuilder: (context, i) {
                    final item = flow.items[i];
                    return switch (item) {
                      MeText(:final text) => ChatBubble(text: text, mine: true),
                      BotText() => _SpokenBubble(
                          item: item,
                          saying: context.read<Speaker>().saying,
                          onListen: () => flow.listen(item),
                        ),
                      BotTyping() => const TypingBubble(),
                      MePhoto(:final path) =>
                        PhotoBubble(image: path, mine: true),
                      MeVoice(:final note) => VoiceNoteBubble(
                          mine: true,
                          duration: note.duration,
                          heard: note.heard ?? 'Listening…',
                          playing: _playing == item,
                          progress: _playing == item ? _progress : 0,
                          onPlay: () => _togglePlay(item, note),
                        ),
                      BotWelcome(:final stats) => WelcomeCard(stats: stats),
                      BotTrades() => TradePicker(
                          picked: flow.pickedTrades,
                          locked: flow.tradesSent,
                          onToggle: flow.toggleTrade,
                        ),
                      BotJobsTeaser() => JobsTeaserCard(
                          teaser: item,
                          onOpen: (_) => flow.cta?.onTap(),
                        ),
                      BotMatches() => MatchesCard(
                          matches: item,
                          onBook: flow.chooseArtisan,
                          onOpen: (a) => context.push(Routes.artisan(a.id)),
                          onSeeAll: () => _open(
                              '${Routes.explore}?category=${item.triage.categoryId}'),
                        ),
                      BotSummary() => SummaryCard(
                          summary: item,
                          active: i == lastSummary &&
                              !flow.items.skip(i).any((x) => x is BotBooked),
                          busy: flow.busy,
                          onConfirm: flow.confirm,
                          onChange: flow.changeBooking,
                          onAddService: () => _addService(flow),
                        ),
                      BotServices() => ServicesCard(
                          item: item,
                          // Only the latest menu takes taps; once you've picked,
                          // it stays as a record.
                          active: i == flow.items.length - 1,
                          onPick: flow.pickService,
                          onOther: flow.askForPrice,
                        ),
                      BotBooked(:final booking) => BookedCard(
                          booking: booking,
                          onOpen: () =>
                              context.push(Routes.booking(booking.id)),
                        ),
                      BotJobPosted() => JobPostedCard(
                          posted: item,
                          onOpen: () =>
                              context.push(Routes.clientJob(item.job.id)),
                        ),
                    };
                  },
                ),
              ),
            ),
            _Bottom(
                flow: flow, focus: _focus, terms: _terms, privacy: _privacy),
          ],
        ),
      ),
    );
  }
}

class _AskHeader extends StatelessWidget {
  const _AskHeader(
      {this.welcome = false, required this.talking, required this.onTalk});

  final bool welcome;

  /// Reading aloud, and the speaker button that turns it on or off.
  final bool talking;
  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final guest = context.select<SessionController, bool>((s) => s.isGuest);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(welcome ? AppSpace.gutter : 4.w, 4.w, 8.w, 8.w),
      child: Row(
        children: [
          if (!welcome)
            AppIconButton(
              icon: IconsaxPlusLinear.arrow_left,
              semanticLabel: 'Back',
              onPressed: () {
                final nav = Navigator.of(context);
                nav.canPop() ? nav.pop() : context.go(Routes.home);
              },
            ),
          const RijHubAvatar(size: 40),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Employi',
                    style: AppText.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    Container(
                      width: 7.w,
                      height: 7.w,
                      decoration: BoxDecoration(
                          color: c.online, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 5.w),
                    Text('Here to help',
                        style:
                            AppText.caption.copyWith(color: c.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: talking
                ? IconsaxPlusLinear.volume_high
                : IconsaxPlusLinear.volume_slash,
            semanticLabel: talking ? 'Stop reading aloud' : 'Read aloud',
            onPressed: onTalk,
          ),
          if (guest)
            AppButton(
              label: 'Sign in',
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: () async {
                final ok = await context
                    .read<AuthGate>()
                    .ensureSignedIn(context, AuthPrompt.join);
                // Signed in from the welcome: into the app.
                if (ok && welcome && context.mounted) context.go(Routes.home);
              },
            ),
        ],
      ),
    );
  }
}

/// One-tap answers, then the input for whatever RijHub is waiting for.
class _Bottom extends StatelessWidget {
  const _Bottom(
      {required this.flow,
      required this.focus,
      required this.terms,
      required this.privacy});

  final AskFlow flow;
  final FocusNode focus;

  /// Open the Terms and the Privacy Policy from the sign-up note.
  final GestureRecognizer terms;
  final GestureRecognizer privacy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final media = context.read<MediaService>();
    return Padding(
      padding: EdgeInsets.only(bottom: 8.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (flow.replies.isNotEmpty)
            ChipRow(children: [
              for (final r in flow.replies)
                PromptChip(
                  label: r.label,
                  icon: r.iconKey == null ? null : CategoryIcons.of(r.iconKey!),
                  solid: r.primary,
                  onTap: r.onTap,
                ),
            ]),
          if (flow.error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(g + 4.w, 0, g, 6.w),
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.info_circle,
                      size: 16.w, color: c.error),
                  SizedBox(width: 6.w),
                  Expanded(
                      child: Text(flow.error!,
                          style: AppText.bodySmall.copyWith(color: c.error))),
                ],
              ),
            ),
          if (flow.mode == ComposerMode.phone)
            Padding(
              padding: EdgeInsets.fromLTRB(g, 2.w, g, 8.w),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: "By continuing you agree to Employi's ",
                      style: AppText.caption.copyWith(color: c.textTertiary)),
                  TextSpan(
                      text: 'Terms',
                      recognizer: terms,
                      style: AppText.caption.copyWith(
                          color: c.textSecondary, fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: ' and ',
                      style: AppText.caption.copyWith(color: c.textTertiary)),
                  TextSpan(
                      text: 'Privacy Policy',
                      recognizer: privacy,
                      style: AppText.caption.copyWith(
                          color: c.textSecondary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: switch (flow.mode) {
              ComposerMode.none => flow.cta == null
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppButton(
                          label: flow.cta!.label,
                          trailing: const Icon(IconsaxPlusLinear.arrow_right),
                          onPressed: flow.cta!.onTap,
                        ),
                        if (flow.cta!.note != null) ...[
                          SizedBox(height: 8.w),
                          Text(flow.cta!.note!,
                              textAlign: TextAlign.center,
                              style: AppText.caption
                                  .copyWith(color: c.textTertiary)),
                        ],
                      ],
                    ),
              ComposerMode.phone => _PhoneInput(flow: flow),
              ComposerMode.code => _CodeInput(flow: flow),
              _ => Composer(
                  focusNode: focus,
                  hint: switch (flow.mode) {
                    ComposerMode.address =>
                      'Street, house number and a landmark',
                    ComposerMode.name => 'Full name, as on your ID',
                    ComposerMode.trade => 'Type or say your trade',
                    _ => 'Type, snap or say it',
                  },
                  enabled: !flow.busy,
                  recording: flow.recording,
                  level: media.level,
                  capitalization: flow.mode == ComposerMode.name
                      ? TextCapitalization.words
                      : TextCapitalization.sentences,
                  onSend: (text) => flow.sendText(text, typed: true),
                  // A photo helps with a problem, not with a name or a trade.
                  onCamera: flow.mode == ComposerMode.name ||
                          flow.mode == ComposerMode.trade
                      ? null
                      : () => _photoChoice(context),
                  onVoiceStart: flow.startVoice,
                  onVoiceCancel: flow.cancelVoice,
                  onVoiceSend: flow.sendVoice,
                ),
            },
          ),
          if (flow.welcome)
            Padding(
              padding: EdgeInsets.fromLTRB(g, 10.w, g, 0),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: "I'm an artisan",
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: const Icon(IconsaxPlusLinear.briefcase),
                      onPressed: flow.artisanWelcome,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: AppButton(
                      label: 'Look around',
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: const Icon(IconsaxPlusLinear.eye),
                      onPressed: flow.lookAround,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _photoChoice(BuildContext context) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectionCard(
                icon: IconsaxPlusLinear.camera,
                title: 'Take a photo',
                subtitle: 'Show what is wrong',
                selected: false,
                onTap: () => Navigator.of(context).pop(true),
              ),
              SizedBox(height: 8.w),
              SelectionCard(
                icon: IconsaxPlusLinear.gallery,
                title: 'Choose from your photos',
                subtitle: 'A photo you already took',
                selected: false,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (camera != null) await flow.sendPhoto(camera: camera);
  }
}

/// The phone number, typed in the conversation.
class _PhoneInput extends StatefulWidget {
  const _PhoneInput({required this.flow});

  final AskFlow flow;

  @override
  State<_PhoneInput> createState() => _PhoneInputState();
}

class _PhoneInputState extends State<_PhoneInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() => widget.flow.sendText(_controller.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56.w,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16.w),
              border: Border.all(color: c.brandStroke, width: 1.6),
            ),
            child: Row(
              children: [
                const NigeriaFlag(width: 22),
                SizedBox(width: 8.w),
                Text('+234', style: AppText.label),
                SizedBox(width: 10.w),
                Container(width: 1, height: 24.w, color: c.border),
                SizedBox(width: 10.w),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational
                    ],
                    inputFormatters: [NigerianPhoneInputFormatter()],
                    onChanged: (_) => widget.flow.clearError(),
                    onSubmitted: (_) => _send(),
                    style: AppText.bodyLarge.copyWith(
                        fontWeight: FontWeight.w500, letterSpacing: 0.3),
                    cursorColor: c.brandStroke,
                    decoration: InputDecoration(
                      hintText: '803 123 4567',
                      hintStyle:
                          AppText.bodyLarge.copyWith(color: c.textTertiary),
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
        SizedBox(width: 8.w),
        RoundAction(
          icon: IconsaxPlusLinear.arrow_up,
          label: 'Send code',
          size: 52,
          onTap: widget.flow.busy ? null : _send,
        ),
      ],
    );
  }
}

/// The 6-digit code, typed in the conversation.
class _CodeInput extends StatefulWidget {
  const _CodeInput({required this.flow});

  final AskFlow flow;

  @override
  State<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<_CodeInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OtpCodeField(
          controller: _controller,
          autofocus: true,
          hasError: widget.flow.error != null,
          onCompleted: (code) {
            HapticFeedback.lightImpact();
            widget.flow.sendText(code);
          },
        ),
        SizedBox(height: 6.w),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppButton(
              label: 'Send a new code',
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: widget.flow.resendCode,
            ),
            Text('·', style: AppText.body.copyWith(color: c.textTertiary)),
            AppButton(
              label: 'Change number',
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: widget.flow.changeNumber,
            ),
          ],
        ),
      ],
    );
  }
}

/// One of RijHub's messages: a tap reads it aloud, and a speaker shows
/// beside it while it's read.
class _SpokenBubble extends StatelessWidget {
  const _SpokenBubble(
      {required this.item, required this.saying, required this.onListen});

  final BotText item;
  final ValueListenable<Object?> saying;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onListen,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        onTapHint: 'Read aloud',
        child: ValueListenableBuilder<Object?>(
          valueListenable: saying,
          builder: (context, now, _) => ChatBubble(
            text: item.text,
            trailing: identical(now, item)
                ? Padding(
                    padding: EdgeInsets.only(left: 6.w, bottom: 8.w),
                    child: Icon(IconsaxPlusBold.volume_high,
                        size: 18.w, color: c.brandStroke),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Formats [n] naira for the cards.
String money(int n) => Naira.format(n);
