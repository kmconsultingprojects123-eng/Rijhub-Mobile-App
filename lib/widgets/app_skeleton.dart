import 'package:flutter/material.dart';

/// Small skeleton helpers to match the app card style. Use these in lists instead
/// of raw CircularProgressIndicators.
class AppSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;
  final bool circle;

  const AppSkeleton({Key? key, this.height = 16, this.width, this.borderRadius = const BorderRadius.all(Radius.circular(8)), this.circle = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12,
        borderRadius: circle ? null : borderRadius,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

