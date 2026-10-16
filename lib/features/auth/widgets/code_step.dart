import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/session.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/repositories.dart';
import 'auth_feedback.dart';
import 'auth_step_header.dart';
import 'auth_step_layout.dart';

/// The second step: the 6-digit code we texted. A number with an account is
/// signed in, which the sheet sees and finishes; a new one goes on to add a
/// name.
class AuthCodeStep extends StatefulWidget {
  const AuthCodeStep({
    super.key,
    required this.onChangeNumber,
    required this.onNeedsDetails,
    required this.onBusyChanged,
  });

  final VoidCallback onChangeNumber;
  final VoidCallback onNeedsDetails;

  /// True while a code is being checked or a new one is on its way, false
  /// once that's done. The sheet holds its back button meanwhile, so going
  /// back can't reset the flow under a request that is still running.
  final ValueChanged<bool> onBusyChanged;

  @override
  State<AuthCodeStep> createState() => _AuthCodeStepState();
}

class _AuthCodeStepState extends State<AuthCodeStep> {
  static const _codeLength = 6;

  late final AuthFlowController _flow;
  late final TextEditingController _code;
  final _focus = FocusNode();
  final _verifyButton = GlobalKey();
  late final _change = TapGestureRecognizer()..onTap = _changeNumber;

  // Read once: the flow clears itself after a sign-in, while this step is
  // still on its way out.
  late final String _phoneDisplay;
  late DateTime _resendAt;

  Timer? _cooldown;
  int _secondsLeft = 0;
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  /// A confirmation, such as where a new code went.
  String? _notice;

  /// The digits last seen, to tell edits apart from caret moves.
  late String _digits;

  /// The code last sent for checking, so each edit is checked once.
  String? _checked;

  bool get _busy => _verifying || _resending;

  @override
  void initState() {
    super.initState();
    _flow = context.read<AuthFlowController>();
    // Non-breaking spaces keep the number on one line.
    _phoneDisplay = _flow.phoneDisplay!.replaceAll(' ', '\u00A0');
    _resendAt = _flow.challenge!.resendAvailableAt;
    _digits = _flow.draftCode;
    _code = TextEditingController(text: _digits)..addListener(_onCodeChanged);
    _startCooldown();
    // Autofocus can't take focus from the step this one replaces.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    _code.dispose();
    _focus.dispose();
    _change.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _secondsLeft = _secondsUntilResend();
    if (_secondsLeft > 0) {
      _cooldown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    final left = _secondsUntilResend();
    if (left == 0) _cooldown?.cancel();
    if (mounted) setState(() => _secondsLeft = left);
  }

  int _secondsUntilResend() {
    final ms = _resendAt.difference(DateTime.now()).inMilliseconds;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  void _onCodeChanged() {
    final text = _code.text;
    if (text == _digits) return; // A caret move, not an edit.
    _digits = text;
    _checked = null;
    // Kept, so a sheet closed to read the SMS reopens with these digits.
    _flow.draftCode = text;
    setState(() {
      _error = null;
      _notice = null;
    });
  }

  void _onCompleted(String code) {
    if (code != _checked) _verify();
  }

  /// Applies [change], which starts or ends a request, and tells the sheet
  /// whether one is still running.
  void _setRequest(VoidCallback change) {
    setState(change);
    widget.onBusyChanged(_busy);
  }

  Future<void> _verify() async {
    final code = _code.text;
    // Not while a new code is on its way: this one is about to be replaced.
    if (_busy || code.length != _codeLength) return;
    _setRequest(() {
      _verifying = true;
      _error = null;
      _notice = null;
      _checked = code;
    });
    try {
      final signedIn = await _flow.verify(code);
      if (!mounted) return;
      if (signedIn == null) {
        // A newer attempt took over while this code was being checked.
        _setRequest(() => _verifying = false);
      } else if (!signedIn) {
        widget.onNeedsDetails();
      }
    } on AuthException catch (e) {
      _verifyFailed(code, e.message);
    } catch (e, s) {
      _verifyFailed(code, reportUnexpectedAuthError(e, s));
    }
  }

  void _verifyFailed(String code, String message) {
    if (!mounted) return;
    final edited = _code.text != code;
    _setRequest(() {
      _verifying = false;
      // The answer is about [code]; if they have changed it since, the
      // message would be about digits no longer on screen.
      if (!edited) _error = message;
    });
    // Check a code they finished while the old one was being checked.
    if (edited) _verify();
  }

  Future<void> _resend(OtpChannel channel) async {
    if (_busy) return;
    final typed = _code.text;
    _setRequest(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      await _flow.resend(channel: channel);
      if (!mounted) return;
      final edited = _code.text != typed;
      // What was there belongs to the old code, which no longer works.
      if (!edited) _code.clear();
      _setRequest(() {
        _resending = false;
        _resendAt = _flow.challenge!.resendAvailableAt;
        _startCooldown();
        _notice = channel == OtpChannel.whatsapp
            ? 'Check WhatsApp for your code.'
            : 'New code sent to $_phoneDisplay.';
      });
      _focus.requestFocus();
      if (edited) {
        // They typed while the new code was on its way.
        _flow.draftCode = _code.text;
        _verify();
      }
    } on AuthException catch (e) {
      _resendFailed(e.message);
    } catch (e, s) {
      _resendFailed(reportUnexpectedAuthError(e, s));
    }
  }

  void _resendFailed(String message) {
    if (!mounted) return;
    _setRequest(() {
      _resending = false;
      _error = message;
    });
  }

  void _changeNumber() => widget.onChangeNumber();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final error = _error;
    final notice = _notice;
    // "Change" waits, like the sheet's back button, while a request runs.
    final canChange = !_busy;
    return AuthStepLayout(
      keepInView: _verifyButton,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthStepHeader.rich(
            title: 'Enter the code',
            message: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'We sent a 6-digit code to '),
                  TextSpan(
                    text: _phoneDisplay,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // The number and "Change" wrap together, never apart.
                  const TextSpan(text: '.\u00A0'),
                  TextSpan(
                    text: 'Change',
                    semanticsLabel: 'Change number',
                    style: TextStyle(
                      color: canChange ? c.brandText : c.textDisabled,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: canChange ? _change : null,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: AppSpace.s24),
          OtpCodeField(
            controller: _code,
            focusNode: _focus,
            autofocus: false,
            onCompleted: _onCompleted,
            hasError: error != null,
          ),
          if (error != null || notice != null) ...[
            SizedBox(height: AppSpace.s12),
            AuthStatusLine(message: error ?? notice!, isError: error != null),
          ],
          SizedBox(height: AppSpace.s8),
          _ResendRow(
            secondsLeft: _secondsLeft,
            isSending: _resending,
            onResend: _verifying ? null : _resend,
          ),
          SizedBox(height: AppSpace.s16),
          AppButton(
            key: _verifyButton,
            label: 'Verify',
            isLoading: _verifying,
            onPressed: _code.text.length == _codeLength && !_resending
                ? _verify
                : null,
          ),
        ],
      ),
    );
  }
}

/// A countdown until a new code can be sent, then the two ways to get one.
/// Always a tap target tall, so nothing below moves when it changes.
class _ResendRow extends StatelessWidget {
  const _ResendRow({
    required this.secondsLeft,
    required this.isSending,
    required this.onResend,
  });

  final int secondsLeft;
  final bool isSending;

  /// Null while a code is being checked.
  final ValueChanged<OtpChannel>? onResend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = AppText.bodySmall.copyWith(color: c.textTertiary);
    final resend = onResend;

    final Widget content;
    if (isSending) {
      content = Text('Sending a new code…', style: quiet);
    } else if (secondsLeft > 0) {
      final minutes = secondsLeft ~/ 60;
      final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
      content = Semantics(
        label: 'Resend code in $secondsLeft '
            '${secondsLeft == 1 ? 'second' : 'seconds'}',
        excludeSemantics: true,
        child: Text(
          'Resend code in $minutes:$seconds',
          // Fixed-width digits, so the line doesn't shimmer as it counts.
          style: quiet.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    } else {
      content = Wrap(
        spacing: AppSpace.s24,
        children: [
          _ResendAction(
            icon: Icon(IconsaxPlusLinear.sms, size: 18.w),
            label: 'Resend code',
            onTap: resend == null ? null : () => resend(OtpChannel.sms),
          ),
          _ResendAction(
            // Brand glyphs fill more of their box than Iconsax, so a size
            // smaller reads the same.
            icon: FaIcon(FontAwesomeIcons.whatsapp, size: 16.w),
            label: 'Get it on WhatsApp',
            onTap: resend == null ? null : () => resend(OtpChannel.whatsapp),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
      child: Align(alignment: AlignmentDirectional.centerStart, child: content),
    );
  }
}

/// A compact text action in the brand colour, with a full 48-point tap area.
class _ResendAction extends StatelessWidget {
  const _ResendAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onTap == null ? c.textDisabled : c.brandText;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      pressedScale: 0.96,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.minTapTarget),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme.merge(data: IconThemeData(color: color), child: icon),
            SizedBox(width: AppSpace.s6),
            Flexible(
              child: Text(
                label,
                style: AppText.labelSmall.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
