import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Helper for safe navigation immediately after account creation/signup.
///
/// Usage:
/// await AccountCreationNavigator.navigateAfterSignup(context, MyHomePage());
class AccountCreationNavigator {
  /// Safe navigation after successful account creation.
  /// Works with GoRouter, page-based Navigator, and traditional Navigator.
  ///
  /// Parameters:
  /// - [context]: BuildContext used for navigation and mounted checks.
  /// - [homePage]: Widget to push when using imperative Navigator APIs.
  /// - [goRoute]: Optional GoRouter route string (e.g. '/home'); defaults to '/home'.
  /// - [preferImperative]: When true, skip calling GoRouter.go() and use
  ///   imperative Navigator pushReplacement instead. Use this when navigating
  ///   to a route that has `requireNoAuth` (like the welcome-after-signup page)
  ///   and the app's router would otherwise redirect away because the user is
  ///   already logged-in.
  static Future<void> navigateAfterSignup(
    BuildContext context,
    Widget homePage, {
    String? goRoute,
    bool preferImperative = false,
  }) async {
    final ts = DateTime.now().toIso8601String();
    debugPrint('NavigationHelper[$ts] -> navigateAfterSignup requested');

    if (!context.mounted) {
      debugPrint(
          'NavigationHelper[$ts] -> context not mounted, aborting navigation');
      return;
    }

    // small debounce to avoid immediate concurrent nav calls
    await Future.delayed(const Duration(milliseconds: 40));

    // Attempt 1: GoRouter if available and caller did not request imperative navigation
    if (!preferImperative) {
      try {
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          final target = goRoute ?? '/home';
          router.go(target);
          return;
        }
      } catch (e, st) {
        // failed
      }

      // small pause between attempts
      await Future.delayed(const Duration(milliseconds: 30));
    }

    // If caller requested imperative navigation AND provided a route name, try
    // a named pushReplacement first. We DO NOT await the result because pushReplacement
    // returns a Future that completes only when the pushed route is popped. We want
    // to return control to the caller immediately so they can proceed (e.g. set auth token).
    if (preferImperative && goRoute != null) {
      try {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacementNamed(goRoute).ignore();
        return;
      } catch (e, st) {
        // failed
      }

      // small pause
      await Future.delayed(const Duration(milliseconds: 20));
    }

    // Utility to detect if current Navigator is page-based
    bool _isPageBasedNavigator(BuildContext ctx) {
      try {
        final navigator = Navigator.of(ctx);
        final widget = navigator.widget;
        // Navigator.widget has a `pages` field when using pages-based API
        final pages = (widget as dynamic).pages;
        return pages != null && (pages as List).isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    // Attempt 2: If app uses page-based Navigator, try a simple push (imperative)
    try {
      final isPages = _isPageBasedNavigator(context);

      if (isPages) {
        if (!context.mounted) return;
        Navigator.of(context)
            .pushReplacement(
              MaterialPageRoute(
                  builder: (_) => homePage,
                  settings: RouteSettings(name: goRoute)),
            )
            .ignore();
        return;
      }
    } catch (e, st) {
      // failed
    }

    // small pause between attempts
    await Future.delayed(const Duration(milliseconds: 30));

    // Attempt 3: Traditional Navigator pushReplacement
    try {
      if (!context.mounted) return;
      Navigator.of(context)
          .pushReplacement(
            MaterialPageRoute(
                builder: (_) => homePage,
                settings: RouteSettings(name: goRoute)),
          )
          .ignore();
      return;
    } catch (e, st) {
      // failed
    }

    // Attempt 4: Root navigator fallback
    try {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushReplacement(
            MaterialPageRoute(
                builder: (_) => homePage,
                settings: RouteSettings(name: goRoute)),
          )
          .ignore();
      return;
    } catch (e, st) {
      // failed
    }

    // Recovery: schedule one retry after a short delay
    try {
      debugPrint(
          'NavigationHelper[$ts] -> scheduling one recovery retry in 250ms');
      await Future.delayed(const Duration(milliseconds: 250));
      if (!context.mounted) return;
      Navigator.of(context)
          .pushReplacement(
            MaterialPageRoute(
                builder: (_) => homePage,
                settings: RouteSettings(name: goRoute)),
          )
          .ignore();
      debugPrint('NavigationHelper[$ts] -> recovery retry dispatched');
      return;
    } catch (e, st) {
      debugPrint('NavigationHelper[$ts] -> recovery retry failed: $e\n$st');
    }

    // Final: Give user-friendly feedback and log
    try {
      debugPrint('NavigationHelper[$ts] -> all navigation attempts failed');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to open home page. Please try again.')),
        );
      }
    } catch (_) {}
  }
}
