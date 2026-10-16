import 'package:flutter/material.dart';
import 'responsive_utils.dart';

class ResponsiveScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final int maxContentWidth;
  final EdgeInsetsGeometry? contentPadding;
  final bool centerContent;
  final bool scrollableBody;
  final bool showRailOnDesktop;

  const ResponsiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.maxContentWidth = 1200,
    this.contentPadding,
    this.centerContent = true,
    this.scrollableBody = true,
    this.showRailOnDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveUtils.isDesktop(context);
    final padding = contentPadding ?? EdgeInsets.symmetric(horizontal: ResponsiveUtils.horizontalPadding(context));
    final constrained = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth.toDouble()),
        child: Padding(padding: padding, child: body),
      ),
    );

    if (isDesktop && showRailOnDesktop) {
      // Desktop layout with optional NavigationRail area on left
      return Scaffold(
        appBar: appBar,
        drawer: drawer,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Placeholder for nav rail; actual app should supply a rail or let this be empty.
              SizedBox(width: 72),
              Expanded(child: scrollableBody ? SingleChildScrollView(child: constrained) : constrained),
            ],
          ),
        ),
      );
    }

    // Mobile / Tablet
    return Scaffold(
      appBar: appBar,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: scrollableBody ? SingleChildScrollView(child: constrained) : constrained,
      ),
    );
  }
}

