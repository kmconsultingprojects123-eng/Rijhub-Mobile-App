import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../services/token_storage.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../utils/auth_token.dart';
import 'dart:async';

class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier._() {
    // Listen to token storage changes and react immediately so the app can
    // resume sessions or clear auth when an external change occurs.
    try {
      _tokenSub = TokenStorage.tokenStream.listen((t) {
        // Update in-memory token and refresh/clear profile accordingly.
        token = t;
        if (t == null || t.isEmpty) {
          profile = null;
          notifyListeners();
        } else {
          // Refresh profile asynchronously; don't block the stream handler.
          Future.microtask(() async {
            try {
              await refreshProfile();
            } catch (_) {
              // ignore
            }
          });
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  static AppStateNotifier? _instance;
  static AppStateNotifier get instance => _instance ??= AppStateNotifier._();

  bool showSplashImage = true;
  String? token;
  Map<String, dynamic>? profile; // cached profile
  bool get loggedIn => token != null && token!.isNotEmpty;
  // Unread notifications count shared across the app
  int unreadNotifications = 0;

  void setUnreadNotifications(int n) {
    unreadNotifications = n;
    notifyListeners();
  }

  Future<void> refreshAuth() async {
    try {
      token = await TokenStorage.getToken();
      // If we have a persisted 'guest' role/token, do not treat it as an
      // authenticated session on app startup. Guests must be explicitly
      // created by user action (tapping "Continue as guest"). This avoids
      // accidental routing leaks where a cached guest token grants access.
      try {
        final persistedRole = await TokenStorage.getRole();
        if ((persistedRole ?? '').toLowerCase() == 'guest') {
          // Remove persisted guest artifacts and treat as not authenticated.
          await TokenStorage.deleteToken();
          await TokenStorage.deleteRole();
          token = null;
          profile = null;
          notifyListeners();
          return;
        }
      } catch (_) {}
      // If there's no token at all, bail out early.
      if (token == null || token!.isEmpty) {
        profile = null;
        notifyListeners();
        return;
      }

      // If the token is expired (or close to expiry), try a refresh token flow.
      if (isTokenExpired(token)) {
        // If there is a persisted refresh token attempt a refresh. If not,
        // we must clear auth and require the user to sign in again.
        final refreshToken = await TokenStorage.getRefreshToken();
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final refreshed = await AuthService.tryRefreshToken(refreshToken);
          if (refreshed != null) {
            // Persist the returned token(s)
            try {
              if (refreshed['token'] != null) {
                final newToken = refreshed['token'].toString();
                await TokenStorage.saveToken(newToken);
                token = newToken;
              }
              if (refreshed['refreshToken'] != null) {
                await TokenStorage.saveRefreshToken(refreshed['refreshToken'].toString());
              }
            } catch (_) {}
          } else {
            // Refresh failed — clear auth and notify listeners.
            await clearAuth();
            return;
          }
        } else {
          // No refresh token available — clear auth (force login).
          await clearAuth();
          return;
        }
      }

      // At this point we have a valid token (either original or refreshed) — fetch profile.
      await refreshProfile();
    } catch (_) {
      token = null;
      profile = null;
      notifyListeners();
    }
  }

  // Fetch and cache the authenticated user's profile.
  Future<void> refreshProfile() async {
    try {
      final p = await UserService.getProfile();
      profile = p != null ? Map<String, dynamic>.from(p) : null;
      notifyListeners();
    } catch (_) {
      // ignore errors but clear profile to avoid stale data
      profile = null;
      notifyListeners();
    }
  }

  // Persist the token when set. If `t` is null, remove from storage.
  Future<void> setToken(String? t) async {
    token = t;
    try {
      if (t == null) {
        await TokenStorage.deleteToken();
        profile = null;
      } else {
        await TokenStorage.saveToken(t);
        // fetch profile after saving token
        await refreshProfile();
      }
    } catch (_) {
      // Swallow storage errors but keep in-memory state consistent.
    }
    notifyListeners();
  }

  /// Public helper to update the in-memory profile and notify listeners.
  /// Use this instead of setting `AppStateNotifier.instance.profile = ...`
  /// from other files so we keep the ChangeNotifier contract consistent.
  void setProfile(Map<String, dynamic>? p) {
    profile = p != null ? Map<String, dynamic>.from(p) : null;
    notifyListeners();
  }

  /// Set a guest session in-memory and persist the role flag so UI can
  /// enable guest behaviour for the current session. We intentionally do
  /// NOT persist a token for guests (guests are unauthenticated by design),
  /// but we persist a role flag so routes/pages can detect guest state.
  Future<void> setGuestSession({Map<String, dynamic>? data}) async {
    token = null; // guests have no auth token
    profile = {
      'isGuest': true,
      'role': 'guest',
      'name': (data != null && data['name'] != null) ? data['name'] : 'Guest',
    };
    try {
      await TokenStorage.saveRole('guest');
    } catch (_) {}
    if (kDebugMode) {
      try {
        debugPrint('AppStateNotifier: guest session set -> ${profile}');
      } catch (_) {}
    }
    notifyListeners();
  }

  // Clear auth both in-memory and in persistent storage.
  Future<void> clearAuth() async {
    token = null;
    profile = null;
    try {
      await TokenStorage.deleteToken();
      // Also remove cached Google profile when clearing auth
      try {
        await TokenStorage.deleteGoogleProfile();
      } catch (_) {}
    } catch (_) {
      // ignore
    }
   // TokenStorage.deleteToken emits a null event to the token stream, so other
    // listeners will be notified. No further action required here.
    notifyListeners();
  }

  void stopShowingSplashImage() {
    showSplashImage = false;
    notifyListeners();
  }

  StreamSubscription<String?>? _tokenSub;

  @override
  void dispose() {
    try {
      _tokenSub?.cancel();
    } catch (_) {}
    super.dispose();
  }
}
