import 'package:flutter/material.dart';
import 'skeleton.dart';

/// A set of common skeleton screen layouts.
class SkeletonScreen extends StatelessWidget {
  final double spacing;
  final bool shaky;
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonScreen({super.key, this.spacing = 12, this.shaky = true, this.baseColor, this.highlightColor});

  /// A skeleton representing a form row: label + input box
  Widget formRow(BuildContext context, {double labelWidth = 120, double height = 48}) {
    return Row(
      children: [
        SizedBox(width: labelWidth, child: AppSkeleton(width: labelWidth, height: 14, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky)),
        SizedBox(width: 12),
        Expanded(child: AppSkeleton(height: height, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky)),
      ],
    );
  }

  /// Skeleton for a profile row: avatar + lines
  Widget profileRow(BuildContext context) {
    return Row(
      children: [
        AppSkeleton(width: 64, height: 64, circular: true, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(height: 16, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky),
              SizedBox(height: 8),
              AppSkeleton(height: 14, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky),
            ],
          ),
        )
      ],
    );
  }

  /// Skeleton for a standard list item
  Widget listItem(BuildContext context) {
    return Row(
      children: [
        AppSkeleton(width: 48, height: 48, circular: true, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [AppSkeleton(height: 16, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky), SizedBox(height: 6), AppSkeleton(height: 12, baseColor: baseColor, highlightColor: highlightColor, shaky: shaky)])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Example composite layout for a form-like skeleton screen
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        profileRow(context),
        SizedBox(height: spacing),
        formRow(context, labelWidth: 100),
        SizedBox(height: spacing),
        formRow(context, labelWidth: 100),
        SizedBox(height: spacing),
        formRow(context, labelWidth: 100),
      ],
    );
  }
}

