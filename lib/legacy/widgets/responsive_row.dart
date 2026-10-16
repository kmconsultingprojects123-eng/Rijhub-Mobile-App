import 'package:flutter/material.dart';

/// Simple helper that uses Row on wide screens and Wrap on narrow screens.
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment wrapAlignment;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.spacing = 12.0,
    this.runSpacing = 12.0,
    this.wrapAlignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final useWrap = w < 520; // threshold where wrapping becomes beneficial

    if (useWrap) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        alignment: wrapAlignment,
        children: children,
      );
    }

    return Row(
      children: children.map((c) => Expanded(child: c)).toList(),
    );
  }
}

