import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import 'widgets/auth_sheet_bar.dart';
import 'widgets/auth_step_layout.dart';
import 'widgets/code_step.dart';
import 'widgets/details_step.dart';
import 'widgets/phone_step.dart';
import 'widgets/success_view.dart';

/// Shows the sign-in sheet over the current screen: a phone number, the
/// code we text to it and, for new numbers, a name. Resolves to true when
/// the person is signed in once the sheet closes.
Future<bool> showAuthSheet(BuildContext context, AuthPrompt prompt) async {
  final session = context.read<SessionController>();
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The sheet draws the theme's handle in its own top row, beside back
    // and close, so the steps sit higher above the keyboard.
    showDragHandle: false,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    constraints: BoxConstraints(
      // Material's width cap, for tablets.
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
    ),
    builder: (context) => _AuthSheet(prompt: prompt),
  );
  return session.isSignedIn;
}

enum _Stage { phone, code, details, success }

class _AuthSheet extends StatefulWidget {
  const _AuthSheet({required this.prompt});

  final AuthPrompt prompt;

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  /// How long "You're all set" shows before the sheet closes.
  static const _successHold = Duration(milliseconds: 900);

  /// The same while a screen reader is on: long enough for it to finish
  /// saying so, as closing the sheet moves it on to the screen underneath.
  static const _spokenSuccessHold = Duration(seconds: 3);

  late final SessionController _session;
  late _Stage _stage;

  /// Whether the last change of step went forward, for the slide direction.
  bool _forward = true;

  /// The number the phone step starts with: the one to correct after
  /// "Change", or one that didn't get as far as a code that still works.
  String? _phoneDraft;
  String? _firstName;

  /// Signed in to an existing account, rather than a new one.
  bool _returning = true;

  /// The step is checking a code, sending a new one or creating the
  /// account. Back waits for it, so the flow isn't reset under a request
  /// that is still running.
  bool _busy = false;
  Timer? _closeTimer;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// The code and name steps can go back to the number.
  bool get _canGoBack => _stage == _Stage.code || _stage == _Stage.details;

  @override
  void initState() {
    super.initState();
    final flow = context.read<AuthFlowController>();
    // begin() drops an attempt whose send failed, was cut short by closing
    // the sheet, or whose code has expired; its number is kept to send
    // again.
    final number = flow.phone;
    // Keeps a recent attempt, so someone who left to read their SMS carries
    // on where they were.
    flow.begin();
    _stage = switch (flow.resumeStep) {
      AuthStep.phone => _Stage.phone,
      AuthStep.code => _Stage.code,
      AuthStep.details => _Stage.details,
    };
    if (_stage == _Stage.phone) _phoneDraft = number;
    // The steps end by signing the person in; the sheet finishes then,
    // whichever step got there.
    _session = context.read<SessionController>()
      ..addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _closeTimer?.cancel();
    super.dispose();
  }

  /// Moves to [next]. Each step scrolls on its own, so it opens at its top.
  void _go(_Stage next) {
    setState(() {
      _forward = next.index > _stage.index;
      _stage = next;
      _busy = false;
    });
  }

  void _setBusy(bool busy) => setState(() => _busy = busy);

  void _changeNumber() {
    final flow = context.read<AuthFlowController>();
    _phoneDraft = flow.phone;
    // Starts over, so a sheet closed now asks for a number when it reopens.
    flow.reset();
    _go(_Stage.phone);
  }

  /// Android's back button. On the code and name steps it goes back to the
  /// number, as the arrow does (closing would only reopen there), and like
  /// the arrow it waits while a request runs.
  Future<bool> _onSystemBack() async {
    if (!_canGoBack || !(ModalRoute.isCurrentOf(context) ?? false)) {
      return false;
    }
    if (!_busy) _changeNumber();
    return true;
  }

  void _onSessionChanged() {
    if (!_session.isSignedIn || _stage == _Stage.success) return;
    _firstName = _session.user?.firstName;
    // Only new numbers reach the details step.
    _returning = _stage != _Stage.details;
    SemanticsService.sendAnnouncement(
      View.of(context),
      "You're all set. "
      '${AuthSuccessView.welcome(_firstName, returning: _returning)}',
      Directionality.of(context),
    );
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    _go(_Stage.success);
    // Held under reduced motion too, where it just doesn't animate.
    _closeTimer = Timer(
      MediaQuery.accessibleNavigationOf(context)
          ? _spokenSuccessHold
          : _successHold,
      _close,
    );
  }

  void _close() {
    // Only while the sheet is on top: it may already be on its way out.
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion;
    Widget steps = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : AppMotion.base,
      layoutBuilder: _layoutSteps,
      transitionBuilder: _transition,
      // Each step pads itself inside the animation, so a sliding step is
      // clipped at the sheet's edges, not the gutter.
      child: KeyedSubtree(key: ValueKey(_stage), child: _buildStep()),
    );
    // AnimatedSize can't run with a zero duration, so under reduced motion
    // the sheet takes each step's height at once.
    if (!reduceMotion) {
      steps = AnimatedSize(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        alignment: Alignment.topCenter,
        child: steps,
      );
    }

    Widget sheet = Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthSheetBar(
            showBack: _canGoBack,
            onBack: _busy ? null : _changeNumber,
            onClose: _close,
          ),
          Flexible(child: steps),
        ],
      ),
    );
    // Android's back button reaches the sheet through the app's router.
    if (Router.maybeOf(context)?.backButtonDispatcher != null) {
      sheet = BackButtonListener(
        onBackButtonPressed: _onSystemBack,
        child: sheet,
      );
    }
    return DoubleTapGuard(child: sheet);
  }

  Widget _buildStep() => switch (_stage) {
        _Stage.phone => AuthPhoneStep(
            prompt: widget.prompt,
            initialPhone: _phoneDraft,
            onCodeSent: () => _go(_Stage.code),
            onNeedsDetails: () => _go(_Stage.details),
          ),
        _Stage.code => AuthCodeStep(
            onChangeNumber: _changeNumber,
            onNeedsDetails: () => _go(_Stage.details),
            onBusyChanged: _setBusy,
          ),
        _Stage.details => AuthDetailsStep(onBusyChanged: _setBusy),
        _Stage.success => AuthStepLayout(
            child: AuthSuccessView(
              firstName: _firstName,
              returning: _returning,
            ),
          ),
      };

  /// Steps stack from the top. A step on its way out takes no space, so the
  /// sheet resizes straight to the new one and clips the old as it shrinks.
  static Widget _layoutSteps(Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [...previous, if (current != null) current],
      );

  /// Fade through with a short slide: the old step leaves in the first 35%
  /// and the new one arrives over the rest, so the two never overlap.
  Widget _transition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // A leaving step's animation runs backwards, from 1 to 0.
        final leaving = animation.status == AnimationStatus.reverse;
        final t = (leaving ? const Interval(0.65, 1) : const Interval(0.35, 1))
            .transform(animation.value);
        final offset = (1 - Curves.easeOutCubic.transform(t)) * 0.06;
        final direction = (_forward ? 1 : -1) * (leaving ? -1 : 1);
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: leaving ? 0 : 1,
          child: IgnorePointer(
            ignoring: leaving,
            child: ExcludeSemantics(
              excluding: leaving,
              child: Opacity(
                opacity: t,
                child: FractionalTranslation(
                  translation: Offset(offset * direction, 0),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
