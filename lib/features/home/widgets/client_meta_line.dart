import 'package:flutter/material.dart';

/// A line of short facts joined by " · ", such as "AC technician · ★ 4.9
/// (128) · 214 jobs".
///
/// When the facts don't fit on one line (large text, a long trade) it
/// breaks between two facts, never inside one, and leaves out the dot at
/// the break. A fact too long for a line of its own wraps at its ordinary
/// spaces rather than losing words to an ellipsis: a booking's time or
/// status matters too much to cut. Keep the words that must stay together
/// ("Free now", "9:00 AM") with non-breaking spaces.
class ClientMetaLine extends StatelessWidget {
  const ClientMetaLine({super.key, required this.parts, required this.style});

  /// The facts, in order. Each may carry its own colour or weight.
  final List<InlineSpan> parts;

  /// The style the facts and dots share.
  final TextStyle style;

  static const _separator = TextSpan(text: ' · ');

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = _lines(constraints.maxWidth, scaler, direction);
        if (lines.length == 1) return _line(lines.single);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [for (final line in lines) _line(line)],
        );
      },
    );
  }

  /// [facts] joined by dots, in [style].
  TextSpan _joined(List<InlineSpan> facts) => TextSpan(
        style: style,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) _separator,
            facts[i],
          ],
        ],
      );

  /// Several facts were measured to fit on one line; the ellipsis only
  /// guards against rounding. A fact on its own may need more than one.
  Widget _line(List<InlineSpan> facts) => facts.length == 1
      ? Text.rich(_joined(facts))
      : Text.rich(
          _joined(facts),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );

  /// Fills each line with as many facts as fit, in order.
  List<List<InlineSpan>> _lines(
    double maxWidth,
    TextScaler scaler,
    TextDirection direction,
  ) {
    double widthOf(List<InlineSpan> facts) {
      final painter = TextPainter(
        text: _joined(facts),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final lines = <List<InlineSpan>>[];
    var current = <InlineSpan>[];
    for (final part in parts) {
      final longer = [...current, part];
      if (current.isEmpty || widthOf(longer) <= maxWidth) {
        current = longer;
      } else {
        lines.add(current);
        current = [part];
      }
    }
    return lines..add(current);
  }
}
