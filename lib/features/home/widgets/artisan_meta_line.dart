import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Short facts on a line with " · " between them, such as "Urgent · 12 min
/// ago · Be the first to quote".
///
/// When they don't all fit (large text, a long area name) the line breaks
/// between two facts and leaves the dot out, so no line starts or ends
/// with one, and a last fact never sits on a line of its own when the one
/// before it can join it. Nothing is cut short: a fact breaks inside
/// itself only when it is too long for a line of its own. Keep a fact's
/// words together with non-breaking spaces where a break would split its
/// meaning ("Today 9–11 PM").
///
/// Facts may carry their own colour, weight or an icon (a `WidgetSpan`).
/// Screen readers skip the dots; give the row a sentence of its own.
class ArtisanMetaLine extends StatelessWidget {
  const ArtisanMetaLine({super.key, required this.facts, required this.style});

  /// The facts, in order.
  final List<InlineSpan> facts;

  /// The style the facts and dots share.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return _FactFlow(
      children: [
        for (final (i, fact) in facts.indexed) ...[
          if (i > 0)
            ExcludeSemantics(
              child: Text(' · ', maxLines: 1, style: style),
            ),
          Text.rich(fact, style: style),
        ],
      ],
    );
  }
}

/// Lays out facts and the dots between them (fact, dot, fact, dot, fact):
/// each fact goes on the current line if it fits after a dot, otherwise
/// it starts the next line and the dot before it is not shown.
class _FactFlow extends MultiChildRenderObjectWidget {
  const _FactFlow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFactFlow(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderFactFlow renderObject) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _FactParentData extends ContainerBoxParentData<RenderBox> {
  /// False for a dot left out at a line break.
  bool shown = true;
}

/// Where each child goes from the start edge, its size, whether it shows,
/// and the size of the whole.
typedef _Flow = ({
  Size size,
  List<Offset> offsets,
  List<Size> sizes,
  List<bool> shown,
});

/// Facts and dots in lines. Its children alternate: fact, dot, fact, dot,
/// fact.
class _RenderFactFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FactParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FactParentData> {
  _RenderFactFlow({required TextDirection textDirection})
      : _textDirection = textDirection;

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FactParentData) {
      child.parentData = _FactParentData();
    }
  }

  /// Places the children in lines no wider than [maxWidth], sizing each
  /// with [sizeOf].
  _Flow _flow(
    double maxWidth,
    Size Function(RenderBox, BoxConstraints) sizeOf,
  ) {
    final children = getChildrenAsList();
    final childConstraints = BoxConstraints(maxWidth: maxWidth);
    final sizes = [
      for (final child in children) sizeOf(child, childConstraints),
    ];
    // Fact f is child 2f; the dot before it, child 2f - 1.
    final facts = (children.length + 1) ~/ 2;
    double factWidth(int f) => sizes[2 * f].width;
    double dotWidth(int f) => f == 0 ? 0 : sizes[2 * f - 1].width;
    // A hair of slack, so a line measured to fit exactly isn't broken by
    // rounding.
    final limit = maxWidth + 0.5;

    // Each fact goes on the current line if it fits after a dot.
    final lines = <List<int>>[];
    var line = <int>[];
    var x = 0.0;
    for (var f = 0; f < facts; f++) {
      if (line.isNotEmpty && x + dotWidth(f) + factWidth(f) <= limit) {
        line.add(f);
        x += dotWidth(f) + factWidth(f);
      } else {
        if (line.isNotEmpty) lines.add(line);
        line = [f];
        x = factWidth(f);
      }
    }
    if (line.isNotEmpty) lines.add(line);

    // A last fact left on a line of its own ("4.6 km", "₦6,000") takes the
    // one before it along, where the two fit together.
    if (lines.length > 1 && lines.last.length == 1) {
      final before = lines[lines.length - 2];
      final last = lines.last.single;
      if (before.length > 1 &&
          factWidth(before.last) + dotWidth(last) + factWidth(last) <= limit) {
        lines.last.insert(0, before.removeLast());
      }
    }

    final offsets = List<Offset>.filled(children.length, Offset.zero);
    final shown = List<bool>.filled(children.length, false);
    var top = 0.0;
    var width = 0.0;
    for (final line in lines) {
      var x = 0.0;
      var height = 0.0;
      for (final (j, f) in line.indexed) {
        if (j > 0) {
          offsets[2 * f - 1] = Offset(x, top);
          shown[2 * f - 1] = true;
          x += dotWidth(f);
          height = math.max(height, sizes[2 * f - 1].height);
        }
        offsets[2 * f] = Offset(x, top);
        shown[2 * f] = true;
        x += factWidth(f);
        height = math.max(height, sizes[2 * f].height);
      }
      width = math.max(width, x);
      top += height;
    }
    return (
      size: Size(math.min(width, maxWidth), top),
      offsets: offsets,
      sizes: sizes,
      shown: shown,
    );
  }

  @override
  void performLayout() {
    final flow = _flow(constraints.maxWidth, (child, childConstraints) {
      child.layout(childConstraints, parentUsesSize: true);
      return child.size;
    });
    size = constraints.constrain(flow.size);
    // Right to left, lines start at the right edge of the final width.
    final rtl = _textDirection == TextDirection.rtl;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      final data = child.parentData! as _FactParentData;
      final start = flow.offsets[i];
      data
        ..offset = rtl
            ? Offset(size.width - start.dx - flow.sizes[i].width, start.dy)
            : start
        ..shown = flow.shown[i];
      child = data.nextSibling;
      i++;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
        _flow(
          constraints.maxWidth,
          (child, childConstraints) => child.getDryLayout(childConstraints),
        ).size,
      );

  @override
  double computeMinIntrinsicWidth(double height) {
    // The widest fact, which may need a line of its own.
    var width = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      if (i.isEven) {
        width = math.max(width, child.getMinIntrinsicWidth(double.infinity));
      }
      child = childAfter(child);
      i++;
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    // Everything on one line.
    var width = 0.0;
    var child = firstChild;
    while (child != null) {
      width += child.getMaxIntrinsicWidth(double.infinity);
      child = childAfter(child);
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _flow(
        width,
        (child, childConstraints) => child.getDryLayout(childConstraints),
      ).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _FactParentData;
      if (data.shown) context.paintChild(child, data.offset + offset);
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final current = child;
      final data = current.parentData! as _FactParentData;
      if (data.shown &&
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                current.hitTest(result, position: transformed),
          )) {
        return true;
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _FactParentData;
      if (data.shown) visitor(child);
      child = data.nextSibling;
    }
  }
}
