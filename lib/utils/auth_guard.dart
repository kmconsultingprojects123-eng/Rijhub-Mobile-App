import 'package:flutter/material.dart';
import '/index.dart';
import '../state/auth_notifier.dart';
import '../pages/login_account/login_account_widget.dart';
import 'navigation_utils.dart';

/// Lightweight auth guard utilities.
///
/// Usage:
///   final ok = await ensureAuthenticatedOrPrompt(context);
///   if (!ok) return; // abort action

Future<bool> isGuestSession() async {
  // Return true when the app is in the unauthenticated state and a prompt
  // should be shown. If the user is a guest or authenticated, we should not
  // show the sign-in prompt here and allow the caller to proceed.
  try {
    return AuthNotifier.instance.status == AuthStatus.unauthenticated;
  } catch (_) {
    return true;
  }
}

Future<bool> ensureAuthenticatedOrPrompt(BuildContext context, {String title = 'Sign in required', String message = 'You need to sign in to continue. Sign in now to access this feature.'}) async {
  // For guest sessions we no longer show modal bottom sheets or dialogs.
  // Instead, redirect the user to the login flow without presenting any
  // intermediate UI. This keeps the guest flow free of modals/sheets as
  // requested.
  final guest = await isGuestSession();
  if (!guest) return true;

  try {
    // Navigate to the login page (no modal/sheet). Caller should abort the
    // original action after this returns false.
    await NavigationUtils.safePushNoAuth(context, LoginAccountWidget());
  } catch (_) {
    try { await NavigationUtils.safePush(context, LoginAccountWidget()); } catch (_) {}
  }

  return false;
}

/// Ensures the current user has a specific role. Returns true if the role
/// matches, otherwise shows an error sheet and optionally redirects to home.
Future<bool> ensureRoleOrRedirect(BuildContext context, String requiredRole, {bool redirectToHome = true}) async {
  // Prefer explicit userRole from AuthNotifier; fall back to profile map if present.
  final roleFromNotifier = AuthNotifier.instance.userRole;
  final profile = AuthNotifier.instance.profile;
  final role = (roleFromNotifier ?? profile?['role']?.toString())?.toLowerCase() ?? '';
  // If the caller is a guest (unauthenticated), do not show a bottom sheet.
  // Redirect the guest into the login flow instead and abort the action.
  try {
    final guest = await isGuestSession();
    if (guest) {
      await ensureAuthenticatedOrPrompt(context);
      return false;
    }
  } catch (_) {}
  if (role.contains(requiredRole.toLowerCase())) return true;

  // Not the required role: show a small information bottom sheet and optionally redirect.
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) {
      final theme = Theme.of(c);
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12.0)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Access denied', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('This page is only available to ${requiredRole}s.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(c).pop(),
                child: Text('OK'),
              ),
            ),
          ]),
        ),
      );
    },
  );

  if (redirectToHome) {
    // Delay navigation to avoid modifying Navigator while the sheet is closing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        NavigationUtils.safePushReplacement(context, HomePageWidget());
      } catch (_) {}
    });
  }

  return false;
}

/// Show a dialog only if the user is authenticated; otherwise redirect to login
Future<T?> showDialogIfAuthed<T>(BuildContext context, {required WidgetBuilder builder, bool barrierDismissible = true}) async {
  try {
    final guest = await isGuestSession();
    if (guest) {
      await ensureAuthenticatedOrPrompt(context);
      return null;
    }
  } catch (_) {}

  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
}

/// Show a modal bottom sheet only for authenticated users; otherwise redirect to login.
Future<T?> showModalBottomSheetIfAuthed<T>(BuildContext context, {required WidgetBuilder builder, bool isScrollControlled = false, Color? backgroundColor, ShapeBorder? shape, Clip? clipBehavior}) async {
  try {
    final guest = await isGuestSession();
    if (guest) {
      await ensureAuthenticatedOrPrompt(context);
      return null;
    }
  } catch (_) {}

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor,
    shape: shape,
    clipBehavior: clipBehavior,
    builder: builder,
  );
}
