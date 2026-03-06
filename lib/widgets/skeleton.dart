import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/skeleton_config.dart';

/// AppSkeleton: shimmering skeleton placeholder used across the app.
/// Accepts optional base and highlight colors to better match brand theme.
class AppSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final bool circular;
  final Duration duration;
  final Color? baseColor;
  final Color? highlightColor;
  final bool shaky;
  /// When true, the skeleton will pulsate opacity (fade) between min and max.
  final bool fade;
  /// Minimum opacity when fading (0.0 - 1.0)
  final double fadeMin;
  /// Maximum opacity when fading (0.0 - 1.0)
  final double fadeMax;

  const AppSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius,
    this.circular = false,
    this.duration = const Duration(milliseconds: 1200),
    this.baseColor,
    this.highlightColor,
    this.shaky = false,
    this.fade = true,
    this.fadeMin = 0.6,
    this.fadeMax = 1.0,
  });

  @override
  _AppSkeletonState createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultBase = theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200;
    // Try to use theme.primaryColor as a subtle highlight if not provided
    final double hlOpacity = theme.brightness == Brightness.dark ? 0.06 : 0.16;
    final defaultHighlight = theme.primaryColor.withAlpha((hlOpacity * 255).round());

    final baseColor = widget.baseColor ?? SkeletonConfig.baseColor ?? defaultBase;
    final highlightColor = widget.highlightColor ?? SkeletonConfig.highlightColor ?? defaultHighlight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // optional subtle vertical motion for the shaky effect
        final double verticalOffset = widget.shaky ? (2.0 * (1.0 - ((math.sin(_controller.value * 2 * math.pi) + 1) / 2))) - 1.0 : 0.0;
        final double translateY = widget.shaky ? (verticalOffset * 2.5) : 0.0;

        // fade opacity modulation
        double opacity = 1.0;
        if (widget.fade) {
          final t = ((math.sin(_controller.value * 2 * math.pi) + 1) / 2);
          opacity = widget.fadeMin + t * (widget.fadeMax - widget.fadeMin);
        }

        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(
            opacity: opacity,
            child: ShaderMask(
              shaderCallback: (rect) {
                final double width = rect.width;
                final shimmerWidth = width / 2;
                final offset = (2 * width) * _controller.value - shimmerWidth;
                final stops = [
                  ((offset - shimmerWidth) / (2 * width)).clamp(0.0, 1.0),
                  (offset / (2 * width)).clamp(0.0, 1.0),
                  ((offset + shimmerWidth) / (2 * width)).clamp(0.0, 1.0),
                ];
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [baseColor, highlightColor, baseColor],
                  stops: stops,
                ).createShader(rect);
              },
              blendMode: BlendMode.srcATop,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: widget.circular ? null : widget.borderRadius ?? BorderRadius.circular(8.0),
                  shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
