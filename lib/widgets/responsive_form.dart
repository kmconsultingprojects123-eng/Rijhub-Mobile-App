import 'package:flutter/material.dart';

class ResponsiveForm extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  final bool center;
  final bool scrollable;

  const ResponsiveForm({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16.0),
    this.center = true,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final calculatedMax = screenW > maxWidth ? maxWidth : screenW;

    final form = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: calculatedMax),
        child: Padding(padding: padding, child: child),
      ),
    );

    return scrollable ? SingleChildScrollView(child: form) : form;
  }
}
