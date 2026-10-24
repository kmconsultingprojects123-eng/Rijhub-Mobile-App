import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import 'app_button.dart';

/// A row of digit boxes backed by one invisible text field, so SMS autofill
/// (iOS "From Messages"), paste and backspace all behave natively. While
/// something is copied, "Paste code" sits under the boxes and fills them
/// from a copied message, such as WhatsApp's "Copy code".
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.hasError = false,
    this.autofocus = true,
    this.focusNode,
    this.readOnly = false,
    this.showPaste = true,
  });

  final TextEditingController controller;
  final int length;

  /// Called when the code changes to a full [length]-digit code. Caret
  /// moves don't call it again.
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool autofocus;

  /// Lets the screen refocus the field, for example after a resend.
  final FocusNode? focusNode;

  /// Blocks edits, for example while a code is being checked.
  final bool readOnly;

  /// Offers "Paste code" while something is copied.
  final bool showPaste;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FocusNode? _ownFocus;
  late final AnimationController _blink;
  late String _lastText;

  /// Whether anything is copied. Asked without reading it: on iOS reading
  /// the clipboard asks the person first, so it's only read on a tap.
  bool _somethingCopied = false;

  /// "Paste code" found no code, which its label says for a moment.
  bool _noCode = false;
  Timer? _noCodeTimer;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    _syncBlink();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
  }

  @override
  void didUpdateWidget(OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _lastText = widget.controller.text;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      // A node of our own is kept until dispose, in case the field goes
      // back to it.
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
    _syncBlink();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from WhatsApp, say, with the code just copied.
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    if (!widget.showPaste) return;
    bool copied;
    try {
      copied = await Clipboard.hasStrings();
    } on Object {
      copied = false;
    }
    if (mounted && copied != _somethingCopied) {
      setState(() => _somethingCopied = copied);
    }
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      text = null;
    }
    if (!mounted) return;
    final code = codeInText(text, widget.length);
    if (code == null) {
      _noCodeTimer?.cancel();
      setState(() => _noCode = true);
      SemanticsService.sendAnnouncement(
        View.of(context),
        _noCodeLabel,
        Directionality.of(context),
      );
      _noCodeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _noCode = false);
      });
      return;
    }
    HapticFeedback.selectionClick();
    widget.controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noCodeTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _ownFocus?.dispose();
    _blink.dispose();
    super.dispose();
  }

  /// Blinks the caret only while one is drawn: focused, editable and not
  /// yet full.
  void _syncBlink() {
    final showsCaret = _focus.hasFocus &&
        !widget.readOnly &&
        widget.controller.text.length < widget.length;
    if (showsCaret && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!showsCaret && _blink.isAnimating) {
      _blink.stop();
    }
  }

  void _onFocusChanged() {
    _syncBlink();
    if (_focus.hasFocus) _checkClipboard();
    setState(() {});
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return; // A caret move, not an edit.
    _lastText = text;
    _syncBlink();
    setState(() {});
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final code = widget.controller.text;
    final gap = AppSpace.s8 + AppSpace.s2;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final canPaste = widget.showPaste && _somethingCopied && !widget.readOnly;

    return Center(
      child: ConstrainedBox(
        // Boxes stop growing at 56pt on wide screens.
        constraints: BoxConstraints(
          maxWidth: widget.length * 56.0 + (widget.length - 1) * gap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _boxes(c, code, gap, ios),
            if (canPaste) ...[
              SizedBox(height: AppSpace.s4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppButton(
                  label: _noCode ? _noCodeLabel : 'Paste code',
                  leading: Icon(IconsaxPlusLinear.clipboard_text, size: 18.w),
                  variant: AppButtonVariant.tertiary,
                  size: AppButtonSize.small,
                  expand: false,
                  onPressed: _noCode ? null : _paste,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _noCodeLabel => 'No ${widget.length}-digit code copied';

  /// The boxes, with the real input on top of them.
  Widget _boxes(AppColors c, String code, double gap, bool ios) {
    return Stack(
      children: [
        // For the eye only. Screen readers find the field below, which
        // has the name and holds the digits.
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1 / 1.16,
                    child: _box(c, code, i),
                  ),
                ),
              ],
            ],
          ),
        ),
        // The real input sits on top, transparent, so taps, long-press
        // paste and autofill reach it directly.
        Positioned.fill(
          child: Semantics(
            label: 'Verification code, ${widget.length} digits',
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              readOnly: widget.readOnly,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              showCursor: false,
              // Paste stays available; the selection handles, which
              // would float over the boxes, are hidden.
              selectionControls:
                  ios ? _NoHandlesCupertino() : _NoHandlesMaterial(),
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _box(AppColors c, String code, int i) {
    final char = i < code.length ? code[i] : '';
    final isActive = _focus.hasFocus &&
        !widget.readOnly &&
        (i == code.length ||
            (code.length == widget.length && i == widget.length - 1));
    // Every box keeps an edge that stands out from the page, so the six
    // places to fill show at a glance, in sunlight too.
    final borderColor = widget.hasError
        ? c.error
        : isActive
            ? c.brandStroke
            : c.inputBorder;

    return AnimatedContainer(
      duration: context.motion(AppMotion.fast),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: char.isNotEmpty ? c.surface : c.surfaceMuted,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: borderColor,
          width: isActive || widget.hasError ? 1.5 : 1,
        ),
      ),
      child: char.isNotEmpty
          ? Text(
              char,
              style: AppText.headline.copyWith(
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            )
          : isActive
              ? FadeTransition(
                  opacity: _blink,
                  child: Container(
                    width: 2,
                    height: AppSpace.s24,
                    color: c.brandStroke,
                  ),
                )
              : null,
    );
  }
}

/// The [length]-digit code in copied [text]: "953276" in "953276 is your
/// verification code.", or in "953 276". Null unless there's exactly one.
String? codeInText(String? text, int length) {
  if (text == null) return null;
  final runs = RegExp('(?<![0-9])[0-9]{$length}(?![0-9])')
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toSet();
  if (runs.length == 1) return runs.single;
  if (runs.isNotEmpty) return null; // Two different codes: not ours to pick.
  final digits = text.replaceAll(RegExp('[^0-9]'), '');
  return digits.length == length ? digits : null;
}

class _NoHandlesMaterial extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) =>
      const SizedBox.shrink();

  @override
  Size getHandleSize(double textLineHeight) => Size.zero;
}

class _NoHandlesCupertino extends CupertinoTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) =>
      const SizedBox.shrink();

  @override
  Size getHandleSize(double textLineHeight) => Size.zero;
}
