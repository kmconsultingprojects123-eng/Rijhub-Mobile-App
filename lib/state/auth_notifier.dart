import 'package:flutter/material.dart';
import '../services/token_storage.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/notification_controller.dart';

enum AuthStatus {
  unauthenticated,
  guest,
  authenticatedClient,
  authenticatedArtisan,
}

class AuthNotifier extends ChangeNotifier {
  AuthNotifier._internal();
  static final AuthNotifier instance = AuthNotifier._internal();

  AuthStatus _status = AuthStatus.unauthenticated;
  Map<String, dynamic>? _profile;
  String? _token;

  AuthStatus get status => _status;
  bool get isGuest => _status == AuthStatus.guest;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticatedClient ||
      _status == AuthStatus.authenticatedArtisan;
  String? get userRole => _profile?['role']?.toString().toLowerCase();
  Map<String, dynamic>? get profile => _profile;
  String? get token => _token;

  /// Refresh authentication state from persistent storage and backend.
  Future<void> refreshAuth() async {
    try {
      final t = await TokenStorage.getToken();
      _token = t;
      if (_token != null && _token!.isNotEmpty) {
        // Token exists — try to load profile and set authenticated status based on role.
        await _refreshProfileAndSetStatus();
      } else {
        _status = AuthStatus.unauthenticated;
        _profile = null;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
      _profile = null;
      _token = null;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _refreshProfileAndSetStatus() async {
    try {
      final prof = await UserService.getProfile();
      if (prof != null) {
        _profile = Map<String, dynamic>.from(prof);
        final role = (_profile?['role'] ?? _profile?['type'] ?? '')
                ?.toString()
                .toLowerCase() ??
            '';
        if (role.contains('artisan')) {
          _status = AuthStatus.authenticatedArtisan;
        } else {
          _status = AuthStatus.authenticatedClient;
        }
      } else {
        // No profile despite token — default to client authenticated to avoid blocking; caller may handle 401s.
        _status = AuthStatus.authenticatedClient;
      }
    } catch (_) {
      // If profile fetch fails, keep token but mark as authenticatedClient as a conservative default.
      _status = AuthStatus.authenticatedClient;
    }

    // Attempt to register device for push notifications if we have a valid token
    if (_token != null && _token!.isNotEmpty) {
      NotificationController.registerDevice(_token);
    }
  }

  /// Called when user completes login. Caller is responsible for navigating after this.
  Future<void> login(String role, {String? token}) async {
    try {
      _token = token ?? _token;
      if (_token != null && _token!.isNotEmpty) {
        await TokenStorage.saveToken(_token!);
      }

      final lower = (role ?? '').toString().toLowerCase();
      if (lower.contains('artisan')) {
        _status = AuthStatus.authenticatedArtisan;
      } else {
        _status = AuthStatus.authenticatedClient;
      }

      // Try to refresh profile but don't block the flow
      try {
        final prof = await UserService.getProfile();
        if (prof != null) _profile = Map<String, dynamic>.from(prof);
      } catch (_) {}

      // Register device for push notifications
      if (_token != null && _token!.isNotEmpty) {
        NotificationController.registerDevice(_token);
      }
    } catch (_) {
      // ignore
    } finally {
      notifyListeners();
    }
  }

  /// Backwards-compatible setter used throughout the codebase. Saves token
  /// and refreshes profile/status.
  Future<void> setToken(String? token) async {
    try {
      _token = token;
      if (token == null || token.isEmpty) {
        await TokenStorage.deleteToken();
        _status = AuthStatus.unauthenticated;
        _profile = null;
      } else {
        await TokenStorage.saveToken(token);
        await _refreshProfileAndSetStatus();
      }
    } catch (_) {
      // ignore
    } finally {
      notifyListeners();
    }
  }

  /// Set guest mode (called when user explicitly chooses Continue as Guest).
  Future<void> setGuest({String? token}) async {
    try {
      _token = token ?? _token;
      if (_token != null && _token!.isNotEmpty) {
        await TokenStorage.saveToken(_token!);
      }
      _status = AuthStatus.guest;
      _profile = null;
    } catch (_) {
      // ignore
    } finally {
      notifyListeners();
    }
  }

  /// Logout: clear token and set to unauthenticated.
  Future<void> logout() async {
    try {
      // Attempt to unregister device before clearing token
      if (_token != null) {
        // Fire and forget unregistration
        NotificationController.unregisterDevice(_token).catchError((_) {});
      }

      _token = null;
      _status = AuthStatus.unauthenticated;
      _profile = null;
      await TokenStorage.deleteToken();
      await AuthService.logout();
    } catch (_) {
      // ignore
    } finally {
      notifyListeners();
    }
  }

  /// Helper to set profile directly
  Future<void> setProfile(Map<String, dynamic>? prof) async {
    _profile = prof != null ? Map<String, dynamic>.from(prof) : null;
    notifyListeners();
  }
}
