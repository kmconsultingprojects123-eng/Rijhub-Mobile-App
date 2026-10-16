import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/auth_gate.dart';
import '../../../app/session.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/repositories.dart';
import 'auth_feedback.dart';
import 'auth_step_header.dart';
import 'auth_step_layout.dart';

/// The sheet's first step: a +234 number, to which we text a 6-digit code.
class AuthPhoneStep extends StatefulWidget {
  const AuthPhoneStep({
    super.key,
    required this.prompt,
    required this.onCodeSent,
    this.initialPhone,
  });

  /// Why the sheet opened. It titles the step.
  final AuthPrompt prompt;
  final VoidCallback onCodeSent;

  /// National digits to start with, for example after "Change".
  final String? initialPhone;

  @override
  State<AuthPhoneStep> createState() => _AuthPhoneStepState();
}

class _AuthPhoneStepState extends State<AuthPhoneStep> {
  static const _invalidNumber =
      'Enter a valid Nigerian mobile number, like 803 123 4567';

  late final _phone = TextEditingController(
    text: NigerianPhone.formatNational(
      NigerianPhone.normalize(widget.initialPhone ?? ''),
    ),
  );
  final _focus = FocusNode();
  final _sendButton = GlobalKey();
  String? _error;

  /// Why a tapped option isn't available yet.
  String? _note;
  bool _sending = false;

  String get _digits => NigerianPhone.normalize(_phone.text);

  @override
  void initState() {
    super.initState();
    // Autofocus can't take focus from the step this one replaces.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Clears the error as they edit, and rebuilds so "Send code" turns on at
  // the tenth digit.
  void _onChanged(String _) => setState(() => _error = null);

  void _onSubmitted(String _) {
    // The done key drops focus. Keep it, so the keyboard stays up through to
    // the code step instead of closing and opening again.
    _focus.requestFocus();
    _continue();
  }

  Future<void> _continue() async {
    if (_sending) return;
    final digits = _digits;
    if (!NigerianPhone.isValid(digits)) {
      setState(() => _error = _invalidNumber);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _note = null;
    });
    try {
      await context.read<AuthFlowController>().sendCode(digits);
      if (mounted) widget.onCodeSent();
    } on AuthException catch (e) {
      _sendFailed(e.message);
    } catch (e, s) {
      _sendFailed(reportUnexpectedAuthError(e, s));
    }
  }

  void _sendFailed(String message) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = message;
    });
  }

  void _showNote(String note) => setState(() => _note = note);

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final note = _note;
    // "Send code" stays beside the field, ahead of the other ways in, so it
    // isn't pinned below them.
    return AuthStepLayout(
      keepInView: _sendButton,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthStepHeader(
            title: widget.prompt.title,
            message: widget.prompt.message,
          ),
          SizedBox(height: AppSpace.s24),
          PhoneNumberField(
            controller: _phone,
            focusNode: _focus,
            autofocus: true,
            errorText: _error,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
          ),
          SizedBox(height: AppSpace.s16),
          AppButton(
            key: _sendButton,
            // Says what happens next: a code is on its way.
            label: 'Send code',
            isLoading: _sending,
            onPressed: _digits.length == 10 ? _continue : null,
          ),
          SizedBox(height: AppSpace.s20),
          const OrDivider(),
          SizedBox(height: AppSpace.s20),
          AppButton(
            label: 'Continue with Google',
            variant: AppButtonVariant.secondary,
            leading: GoogleMark(size: AppSize.icon),
            onPressed: () => _showNote(
                'Google sign-in is coming soon. Use your phone number for now.'),
          ),
          if (isIOS) ...[
            SizedBox(height: AppSpace.s12),
            AppButton(
              label: 'Continue with Apple',
              variant: AppButtonVariant.secondary,
              leading: Icon(Icons.apple, size: AppSize.iconLarge),
              onPressed: () => _showNote(
                  'Apple sign-in is coming soon. Use your phone number for now.'),
            ),
          ],
          if (note != null) ...[
            SizedBox(height: AppSpace.s16),
            AuthNote(message: note),
          ],
          SizedBox(height: AppSpace.s24),
          _LegalNote(
            onOpen: () => _showNote(
              'Our new Terms and Privacy pages are coming with the new website.',
            ),
          ),
        ],
      ),
    );
  }
}

/// "By continuing, you agree to…", with both documents as links.
class _LegalNote extends StatefulWidget {
  const _LegalNote({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_LegalNote> createState() => _LegalNoteState();
}

class _LegalNoteState extends State<_LegalNote> {
  late final _terms = TapGestureRecognizer()..onTap = _open;
  late final _privacy = TapGestureRecognizer()..onTap = _open;

  void _open() => widget.onOpen();

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final link = TextStyle(color: c.brandText, fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        text: "By continuing, you agree to RijHub's ",
        // Non-breaking spaces keep "Terms and Privacy Policy" on one line.
        children: [
          TextSpan(text: 'Terms', style: link, recognizer: _terms),
          const TextSpan(text: '\u00A0and\u00A0'),
          TextSpan(
            text: 'Privacy\u00A0Policy',
            style: link,
            recognizer: _privacy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: AppText.caption.copyWith(color: c.textTertiary),
    );
  }
}
