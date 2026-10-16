import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// A step of the sign-in sheet: its content, which scrolls when the sheet
/// is too short for it, with the step's main button always in view above
/// the keyboard: pinned below the content, or kept in view within it.
class AuthStepLayout extends StatefulWidget {
  const AuthStepLayout({
    super.key,
    required this.child,
    this.action,
    this.keepInView,
  });

  final Widget child;

  /// The main button, pinned below the content, for a step whose content
  /// can run long (the name step's list of trades).
  final Widget? action;

  /// The main button of a step with short content, which keeps it beside
  /// its field. As the keyboard rises, the content scrolls to keep it in
  /// view on a small phone or with large text.
  final GlobalKey? keepInView;

  @override
  State<AuthStepLayout> createState() => _AuthStepLayoutState();
}

class _AuthStepLayoutState extends State<AuthStepLayout> {
  /// Content has scrolled up under the sheet's top row.
  bool _above = false;

  /// Content runs on below, under the pinned button.
  bool _below = false;

  /// The keyboard's height when last seen.
  double _keyboard = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > _keyboard && widget.keepInView != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
    _keyboard = keyboard;
  }

  void _reveal() {
    final button = widget.keepInView?.currentContext;
    if (button == null) return;
    Scrollable.ensureVisible(
      button,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  bool _onScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      ScrollUpdateNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics != null) {
      final above = metrics.extentBefore > 0;
      final below = metrics.extentAfter > 0;
      if (above != _above || below != _below) {
        setState(() {
          _above = above;
          _below = below;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final action = widget.action;
    final bottom = AppSpace.s16 + MediaQuery.paddingOf(context).bottom;
    BorderSide edge(bool shown) =>
        BorderSide(color: shown ? c.border : Colors.transparent);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: NotificationListener<Notification>(
            onNotification: _onScroll,
            // A hairline where content runs on out of sight, as on the tab
            // bar, so cut-off content reads as scrolled, not broken.
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border(
                  top: edge(_above),
                  bottom: edge(_below && action != null),
                ),
              ),
              child: GestureDetector(
                // Tapping outside a field puts the keyboard away.
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.s8,
                    AppSpace.gutter,
                    action == null ? bottom : 0,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        if (action != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.s16,
              AppSpace.gutter,
              bottom,
            ),
            child: action,
          ),
      ],
    );
  }
}
