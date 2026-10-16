import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Makes any surface tappable with a quiet press response: it shrinks a
/// little while held. Cards, tiles and rows use this instead of ink ripples.
///
/// It also takes keyboard and switch focus, shows a ring while focused that
/// way, and activates with Enter or Space.
///
/// Pass [semanticLabel] when the child's text alone doesn't describe the
/// action; it then replaces the child's semantics so nothing is read twice.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.pressedScale = 0.98,
    this.focusRadius,
    this.focusOffset = 3,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double pressedScale;

  /// The corners of the focus ring, to match the child's. Defaults to the
  /// medium radius.
  final BorderRadius? focusRadius;

  /// How far outside the child's edges the focus ring sits, so it never
  /// covers what the child shows. Use 0 when the child has touch padding
  /// around what it draws, or sits in a list that clips its edges.
  final double focusOffset;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  /// Focused from a keyboard or switch, so the ring shows. Touch never
  /// shows it.
  bool _showFocus = false;

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTap?.call();
        return null;
      },
    ),
  };

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: widget.semanticLabel != null ? widget.onTap : null,
      excludeSemantics: widget.semanticLabel != null,
      child: FocusableActionDetector(
        enabled: enabled,
        actions: _actions,
        // Screen readers move a focus of their own; this one is for
        // keyboards and switches, so it adds nothing to what they read.
        includeFocusSemantics: false,
        onShowFocusHighlight: (show) => setState(() => _showFocus = show),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          child: AnimatedScale(
            scale: _pressed ? widget.pressedScale : 1,
            duration: reduceMotion ? Duration.zero : AppMotion.fast,
            curve: AppMotion.standard,
            child: CustomPaint(
              foregroundPainter: _showFocus
                  ? _FocusRing(
                      radius: widget.focusRadius ?? AppRadius.mdAll,
                      offset: widget.focusOffset,
                      outer: c.textPrimary,
                      inner: c.background,
                    )
                  : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring in the text colour with a hairline of the page colour inside it,
/// so one of the two stands out on any surface, crimson and photos included.
class _FocusRing extends CustomPainter {
  _FocusRing({
    required this.radius,
    required this.offset,
    required this.outer,
    required this.inner,
  });

  final BorderRadius radius;
  final double offset;
  final Color outer;
  final Color inner;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = radius.toRRect(Offset.zero & size).inflate(offset);
    final paint = Paint()..style = PaintingStyle.stroke;
    canvas
      ..drawRRect(
        edge.deflate(1),
        paint
          ..color = outer
          ..strokeWidth = 2,
      )
      ..drawRRect(
        edge.deflate(2.5),
        paint
          ..color = inner
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_FocusRing old) =>
      old.radius != radius ||
      old.offset != offset ||
      old.outer != outer ||
      old.inner != inner;
}
