import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import 'chat.dart';

/// The Ask bar: where people say what's wrong in their own words, a photo
/// or a voice note. On the home screen it is an entry point (tapping it
/// opens the conversation); in a conversation, [Composer] takes its place.
class AskBar extends StatelessWidget {
  const AskBar({
    super.key,
    required this.onTap,
    required this.onCamera,
    required this.onMic,
    this.hint = 'Describe it, snap it or say it',
    this.floating = false,
  });

  final VoidCallback onTap;
  final VoidCallback onCamera;
  final VoidCallback onMic;
  final String hint;

  /// Over a map or photo: a soft shadow instead of an outline.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = 56.w;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.pillAll,
        border: floating ? null : Border.all(color: c.borderStrong),
        boxShadow: floating
            ? AppShadows.floating
            : const [
                BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 16,
                    offset: Offset(0, 4)),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: hint,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(left: 18.w),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: c.textTertiary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _RoundAction(
            icon: IconsaxPlusLinear.camera,
            label: 'Add a photo',
            onTap: onCamera,
          ),
          SizedBox(width: 2.w),
          Padding(
            padding: EdgeInsets.only(right: 6.w),
            child: _RoundAction(
              icon: IconsaxPlusBold.microphone_2,
              label: 'Record a voice note',
              onTap: onMic,
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = 44.w;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48.w,
          height: 48.w,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: filled ? c.brand : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: filled ? 20.w : 22.w,
                color: filled ? c.onBrand : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The input at the bottom of a conversation: words, a photo, or a voice
/// note. The microphone turns into send once something is typed.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    required this.onCamera,
    required this.onVoiceStart,
    required this.onVoiceCancel,
    required this.onVoiceSend,
    this.recording = false,
    this.level,
    this.hint = 'Type, snap or say it',
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.capitalization = TextCapitalization.sentences,
  });

  final ValueChanged<String> onSend;

  /// Null where a photo can't help (a name, a trade): no camera button.
  final VoidCallback? onCamera;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceCancel;
  final VoidCallback onVoiceSend;

  /// A voice note is being recorded: the bar shows the recording.
  final bool recording;
  final Stream<double>? level;
  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final TextCapitalization capitalization;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.recording) {
      return RecordingBar(
        onCancel: widget.onVoiceCancel,
        onSend: widget.onVoiceSend,
        level: widget.level,
      );
    }
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      constraints: BoxConstraints(minHeight: 56.w),
      padding: EdgeInsets.only(left: 18.w, right: 6.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(28.w),
        border: Border.all(color: c.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4.w),
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textCapitalization: widget.capitalization,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: AppText.body,
                cursorColor: c.brandStroke,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: AppText.body.copyWith(color: c.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.w),
                ),
              ),
            ),
          ),
          if (!hasText && widget.onCamera != null)
            _RoundAction(
              icon: IconsaxPlusLinear.camera,
              label: 'Add a photo',
              onTap: widget.enabled ? widget.onCamera : null,
            ),
          Padding(
            padding: EdgeInsets.only(bottom: 4.w),
            child: _RoundAction(
              icon: hasText
                  ? IconsaxPlusLinear.arrow_up
                  : IconsaxPlusBold.microphone_2,
              label: hasText ? 'Send' : 'Record a voice note',
              onTap: widget.enabled
                  ? (hasText ? _send : widget.onVoiceStart)
                  : null,
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-tap answer or common problem, with an icon.
class PromptChip extends StatelessWidget {
  const PromptChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.solid = false,
    this.floating = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Picked in a multi-choice: crimson outline and a tick.
  final bool selected;

  /// The active filter: solid black.
  final bool solid;

  /// Over a map: white with a shadow.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg =
        solid ? c.onSurfaceStrong : (selected ? c.brandText : c.textPrimary);
    return Semantics(
      button: true,
      selected: selected || solid,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5.w),
          child: Container(
            height: 38.w,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: solid
                  ? c.surfaceStrong
                  : (selected ? c.brandSubtle : c.surface),
              borderRadius: AppRadius.pillAll,
              border: solid
                  ? null
                  : Border.all(
                      color: selected
                          ? c.brandStroke
                          : (floating ? Colors.transparent : c.border),
                      width: selected ? 1.4 : 1,
                    ),
              boxShadow: floating ? AppShadows.floating : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null && !selected) ...[
                  Icon(icon, size: 16.w, color: fg),
                  SizedBox(width: 6.w),
                ],
                if (selected) ...[
                  Icon(IconsaxPlusBold.tick_circle,
                      size: 16.w, color: c.brandStroke),
                  SizedBox(width: 6.w),
                ],
                Text(label, style: AppText.labelSmall.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chips in one row that scrolls sideways, starting at the screen's edge.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48.w,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: padding ?? EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}
