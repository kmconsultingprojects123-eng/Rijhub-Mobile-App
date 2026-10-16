import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Wrap every bottom sheet's content in this. It keeps the second tap of a
/// quick double tap on whatever opened the sheet,
/// which lands on the scrim as the sheet rises, from closing it again: a
/// tap that starts within [kDoubleTapTimeout] of the sheet appearing can't
/// pop it (nor can Android's back in that moment). Close, dragging the sheet
/// down and later taps on the scrim close it as usual.
class DoubleTapGuard extends StatefulWidget {
  const DoubleTapGuard({super.key, required this.child});

  final Widget child;

  @override
  State<DoubleTapGuard> createState() => _DoubleTapGuardState();
}

class _DoubleTapGuardState extends State<DoubleTapGuard> {
  late final Timer _timer;
  bool _justOpened = true;

  /// Pointers that went down while the sheet had just opened, and haven't
  /// lifted yet.
  final _early = <int>{};
  bool _canClose = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kDoubleTapTimeout, () {
      _justOpened = false;
      _update();
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    _timer.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent && _justOpened) {
      _early.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      // The scrim has already taken this lift as a tap, before the sheet
      // can rebuild, so an early tap stays harmless to the end.
      if (_early.remove(event.pointer)) _update();
    }
  }

  void _update() {
    final canClose = !_justOpened && _early.isEmpty;
    if (mounted && canClose != _canClose) {
      setState(() => _canClose = canClose);
    }
  }

  @override
  Widget build(BuildContext context) =>
      PopScope(canPop: _canClose, child: widget.child);
}
