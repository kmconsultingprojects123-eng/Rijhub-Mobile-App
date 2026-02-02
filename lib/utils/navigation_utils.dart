import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../utils/auth_guard.dart';
import '../services/navigation_service.dart';
import '../state/app_state_notifier.dart';
import '/index.dart';
import '/main.dart';
import '../services/flow_guard.dart';

/// Navigation helpers that delegate to [NavigationService.instance] which
/// serializes navigation calls. These helpers preserve the previous
/// guest-auth prompting behavior where needed.
class NavigationUtils {
  /// Like previous safePush: prompts guest users if required, then navigates.
  static Future<T?> safePush<T>(BuildContext context, Widget page) async {
    try {
      final guest = await (() async {
        try {
          return await isGuestSession();
        } catch (_) {
          return false;
        }
      })();
      if (guest) {
        final ok = await ensureAuthenticatedOrPrompt(context);
        if (!ok) return null;
      }
    } catch (_) {}

    if (!context.mounted) return null;

    // If the target page looks like an auth/onboarding page and the user is
    // already logged in, avoid pushing it onto the stack — replace the
    // navigation stack with the appropriate home page so Back won't return
    // to auth screens.
    try {
      final loggedIn = AppStateNotifier.instance.loggedIn;
      if (loggedIn) {
        final authTargets = [
          'LoginAccountWidget',
          'CreateAccount2Widget',
          'WelcomeAfterSignupWidget',
        ];
        final runtimeName = page.runtimeType.toString();
        if (authTargets.contains(runtimeName)) {
          final profile = AppStateNotifier.instance.profile;
          final roleStr = (profile?['role']?.toString() ?? '').toLowerCase();
          final bool isArtisan = roleStr.contains('artisan');
          final Widget home = isArtisan ? NavBarPage(initialPage: 'homePage') : HomePageWidget();
          await NavigationService.instance.pushAndRemoveWidgetUntil(context, home, (r) => false);
          return null;
        }
      }
    } catch (_) {}

    return NavigationService.instance.pushWidget<T>(context, page);
  }

  /// Unconditional push used for onboarding flows where guest prompts should
  /// not appear.
  static Future<T?> safePushNoAuth<T>(BuildContext context, Widget page) async {
    if (!context.mounted) return null;

    try {
      // If user is already logged in, avoid navigating to a "no-auth" page
      // such as login/signup/welcome. Instead, replace the entire stack with
      // the appropriate home page for the current role so the back button
      // doesn't return to auth screens.
      final loggedIn = AppStateNotifier.instance.loggedIn;
      if (loggedIn) {
        final profile = AppStateNotifier.instance.profile;
        final roleStr = (profile?['role']?.toString() ?? '').toLowerCase();
        final bool isArtisan = roleStr.contains('artisan');
        final Widget home = isArtisan ? NavBarPage(initialPage: 'homePage') : HomePageWidget();
        await NavigationService.instance.pushAndRemoveWidgetUntil(context, home, (r) => false);
        return null;
      }
    } catch (_) {}

    return NavigationService.instance.pushWidget<T>(context, page);
  }

  /// Replace the current with [page].
  static Future<T?> safePushReplacement<T>(BuildContext context, Widget page) async {
    if (!context.mounted) return null;
    return NavigationService.instance.pushReplacementWidget<T, T>(context, page);
  }

  static Future<void> safeReplaceAllWith(BuildContext context, Widget page) async {
    if (!context.mounted) return;

    // Debugging aid: log caller stack and page type so we can trace unexpected
    // replace-all navigations which may cause the app to jump to /homePage.
    try {
      final st = StackTrace.current.toString().split('\n').take(12).join(' | ');
      debugPrint('NavigationUtils.safeReplaceAllWith called for page=${page.runtimeType}; caller stack (truncated): $st');
    } catch (_) {}

    // If a payment flow is active, wait a short bounded time for it to finish
    // to avoid interrupting critical payment UX. Wait up to 5 seconds polling.
    try {
      var waited = 0;
      while (FlowGuard.isPaymentActive && waited < 5000) {
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }
      if (FlowGuard.isPaymentActive) {
        debugPrint('safeReplaceAllWith: payment still active after wait — skipping replace-all to avoid interrupting payment flow');
        return;
      }
    } catch (_) {}

    await NavigationService.instance.pushAndRemoveWidgetUntil(context, page, (r) => false);
  }

  static void safeMaybePop(BuildContext context, [Object? result]) {
    // Pop operations are serialized via the service to avoid races.
    NavigationService.instance.pop(context, result as dynamic);
  }

  static void safePop(BuildContext context, [Object? result]) {
    NavigationService.instance.pop(context, result as dynamic);
  }
}
