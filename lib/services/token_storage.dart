import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/material.dart' show debugPrint;
import 'dart:async';

class TokenStorage {
  // Broadcast stream to notify listeners when auth token changes.
  static final StreamController<String?> _tokenController = StreamController<String?>.broadcast();
  static Stream<String?> get tokenStream => _tokenController.stream;

  static const _keyToken = 'auth_token';
  static const _keyRole = 'user_role';
  static const _keyKycVerified = 'kyc_verified';
  // New: key to store the KYC status string returned by backend (e.g., 'pending','approved','rejected')
  static const _keyKycStatus = 'kyc_status';
  static const _keyRecentName = 'recent_name';
  static const _keyRecentEmail = 'recent_email';
  static const _keyRecentPhone = 'recent_phone';
  // Key for storing a cached Google profile (JSON encoded)
  static const _keyGoogleProfile = 'google_profile';
  static const _keyRefreshToken = 'refresh_token';
  // Keys for storing user's canonical location/address used throughout the app
  static const _keyLocationAddress = 'user_location_address';
  static const _keyLocationLat = 'user_location_lat';
  static const _keyLocationLon = 'user_location_lon';
  // Keys for caching artisan dashboard/profile JSON
  static const _keyDashboardProfile = 'artisan_dashboard_profile';
  static const _keyDashboardData = 'artisan_dashboard_data';
  // Prefix used to namespace dashboard caches per userId when available
  static const _keyDashboardPrefix = 'artisan_dashboard';

  // New: key for "remember me" feature and remembered email
  static const _keyRememberMe = 'remember_me';
  static const _keyRememberedEmail = 'remembered_email';

  // Helper to build a dashboard key; if userId is provided or can be read from
  // stored user info, return a namespaced key `artisan_dashboard:<userId>:<base>`.
  // Falls back to the legacy baseKey when no userId is available to remain
  // backwards-compatible.
  static Future<String> _dashboardKey(String baseKey, {String? userId}) async {
    try {
      userId ??= await TokenStorage.getUserId();
    } catch (_) {
      userId = null;
    }
    if (userId != null && userId.isNotEmpty) {
      return '$_keyDashboardPrefix:$userId:$baseKey';
    }
    return baseKey; // legacy fallback
  }

  // Flag to avoid repeatedly showing the onboarding reminder
  static const _keyOnboardReminderShown = 'onboard_reminder_shown';

  // Lazily create FlutterSecureStorage to avoid keystore initialization issues
  // on some Android devices. If creation fails, _secureAvailable will be false
  // and we fall back to SharedPreferences for persistence.
  static FlutterSecureStorage? _secureStorage;
  static bool _secureAvailable = true;

  static Future<FlutterSecureStorage?> _getSecureStorage() async {
    if (kIsWeb) return null;
    if (!_secureAvailable) return null;
    if (_secureStorage != null) return _secureStorage;
    try {
      _secureStorage = const FlutterSecureStorage();
      return _secureStorage;
    } catch (e, st) {
      // TokenStorage: secure storage init failed; do not print to terminal for security.
      _secureAvailable = false;
      _secureStorage = null;
      return null;
    }
  }

  static Future<void> saveToken(String token) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyToken, token);
      } else {
        // attempt secure write; fall back to SharedPreferences on failure
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.write(key: _keyToken, value: token);
          } catch (e) {
            // secure write token failed; avoid printing to terminal for security
            _secureAvailable = false;
          }
        }
        // persist to SharedPreferences as a reliable fallback
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyToken, token);
        } catch (_) {}
      }
    } catch (_) {}
    // Emit token change so listeners across the app can react immediately.
    try {
      _tokenController.add(token);
    } catch (_) {}
  }

  static Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_keyToken);
      }
      // Try secure storage first (if available)
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          final token = await s.read(key: _keyToken);
          if (token != null && token.isNotEmpty) return token;
        } catch (e) {
          // secure read token failed; avoid printing to terminal for security
          _secureAvailable = false;
        }
      }
      // Fallback to SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final t = prefs.getString(_keyToken);
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyToken);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.delete(key: _keyToken);
          } catch (e) {
            // secure delete token failed; avoid printing to terminal for security
            _secureAvailable = false;
          }
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_keyToken);
        } catch (_) {}
      }
    } catch (_) {}
    // Notify listeners that token was removed
    try {
      _tokenController.add(null);
    } catch (_) {}
  }

  // Persist a canonical role string (e.g. 'artisan' or 'customer') so UI
  // can route users after login without re-parsing responses repeatedly.
  static Future<void> saveRole(String role) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRole, role);
    } else {
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          await s.write(key: _keyRole, value: role);
        } catch (e) {
          debugPrint('TokenStorage: secure write role failed: $e');
          _secureAvailable = false;
        }
      } else {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyRole, role);
        } catch (_) {}
      }
    }
  }

  static Future<String?> getRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRole);
    }
    final s = await _getSecureStorage();
    if (s != null) {
      try {
        return await s.read(key: _keyRole);
      } catch (e) {
        debugPrint('TokenStorage: secure read role failed: $e');
        _secureAvailable = false;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRole);
    } catch (_) {}
    return null;
  }

  static Future<void> deleteRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRole);
    } else {
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          await s.delete(key: _keyRole);
        } catch (e) {
          debugPrint('TokenStorage: secure delete role failed: $e');
          _secureAvailable = false;
        }
      }
    }
  }

  // Retrieve cached dashboard data (decoded payload) if present.
  static Future<Map<String, dynamic>?> getDashboardData() async {
    String? jsonStr;
    try {
      final key = await _dashboardKey(_keyDashboardData);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(key) ?? prefs.getString(_keyDashboardData);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          jsonStr = await s.read(key: key) ?? await s.read(key: _keyDashboardData);
        } else {
          final prefs = await SharedPreferences.getInstance();
          jsonStr = prefs.getString(key) ?? prefs.getString(_keyDashboardData);
        }
      }
      if (jsonStr == null || jsonStr.isEmpty) return null;
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map && decoded['payload'] is Map) return Map<String, dynamic>.from(decoded['payload']);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  // Delete any cached dashboard keys (namespaced or legacy) to force refresh
  static Future<void> deleteDashboardCache() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyDashboardData);
        await prefs.remove(_keyDashboardProfile);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.delete(key: _keyDashboardData);
            await s.delete(key: _keyDashboardProfile);
          } catch (_) {}
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.containsKey(_keyDashboardData)) await prefs.remove(_keyDashboardData);
          if (prefs.containsKey(_keyDashboardProfile)) await prefs.remove(_keyDashboardProfile);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // New: persist a simple KYC verified flag so UI can optimistically show
  // the verified badge immediately after a successful KYC flow.
  static Future<void> saveKycVerified(bool verified) async {
    final val = verified ? 'true' : 'false';
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyKycVerified, val);
    } else {
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          await s.write(key: _keyKycVerified, value: val);
        } catch (e) {
          debugPrint('TokenStorage: secure write kyc_verified failed: $e');
          _secureAvailable = false;
        }
      } else {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyKycVerified, val);
        } catch (_) {}
      }
    }
  }

  static Future<bool?> getKycVerified() async {
    String? raw;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_keyKycVerified);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          raw = await s.read(key: _keyKycVerified);
        } else {
          final prefs = await SharedPreferences.getInstance();
          raw = prefs.getString(_keyKycVerified);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getKycVerified failed: $e');
      return null;
    }
    if (raw == null) return null;
    return raw.toLowerCase() == 'true';
  }

  static Future<void> deleteKycVerified() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyKycVerified);
    } else {
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          await s.delete(key: _keyKycVerified);
        } catch (e) {
          debugPrint('TokenStorage: secure delete kyc_verified failed: $e');
          _secureAvailable = false;
        }
      }
    }
  }

  /// Persist a canonical location/address and optional coordinates so UI
  /// across the app can access the user's last known service address quickly.
  static Future<void> saveLocation({String? address, double? latitude, double? longitude}) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        if (address != null) await prefs.setString(_keyLocationAddress, address);
        if (latitude != null) await prefs.setString(_keyLocationLat, latitude.toString());
        if (longitude != null) await prefs.setString(_keyLocationLon, longitude.toString());
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          if (address != null) await s.write(key: _keyLocationAddress, value: address);
          if (latitude != null) await s.write(key: _keyLocationLat, value: latitude.toString());
          if (longitude != null) await s.write(key: _keyLocationLon, value: longitude.toString());
        } else {
          final prefs = await SharedPreferences.getInstance();
          if (address != null) await prefs.setString(_keyLocationAddress, address);
          if (latitude != null) await prefs.setString(_keyLocationLat, latitude.toString());
          if (longitude != null) await prefs.setString(_keyLocationLon, longitude.toString());
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveLocation failed: $e');
    }
  }

  /// Retrieve the cached location object if available. Returns a map with keys
  /// 'address' (String?), 'latitude' (double?) and 'longitude' (double?).
  static Future<Map<String, dynamic>> getLocation() async {
    String? addr;
    String? latRaw;
    String? lonRaw;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        addr = prefs.getString(_keyLocationAddress);
        latRaw = prefs.getString(_keyLocationLat);
        lonRaw = prefs.getString(_keyLocationLon);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          addr = await s.read(key: _keyLocationAddress);
          latRaw = await s.read(key: _keyLocationLat);
          lonRaw = await s.read(key: _keyLocationLon);
        } else {
          final prefs = await SharedPreferences.getInstance();
          addr = prefs.getString(_keyLocationAddress);
          latRaw = prefs.getString(_keyLocationLat);
          lonRaw = prefs.getString(_keyLocationLon);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getLocation failed: $e');
      return {'address': null, 'latitude': null, 'longitude': null};
    }
    double? lat; double? lon;
    if (latRaw != null && latRaw.isNotEmpty) lat = double.tryParse(latRaw);
    if (lonRaw != null && lonRaw.isNotEmpty) lon = double.tryParse(lonRaw);
    return {'address': addr, 'latitude': lat, 'longitude': lon};
  }

  static Future<void> deleteLocation() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyLocationAddress);
        await prefs.remove(_keyLocationLat);
        await prefs.remove(_keyLocationLon);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.delete(key: _keyLocationAddress);
            await s.delete(key: _keyLocationLat);
            await s.delete(key: _keyLocationLon);
          } catch (e) {
            debugPrint('TokenStorage: deleteLocation secure failed: $e');
            _secureAvailable = false;
          }
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_keyLocationAddress);
          await prefs.remove(_keyLocationLat);
          await prefs.remove(_keyLocationLon);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('TokenStorage: deleteLocation failed: $e');
    }
  }

  // Persist a small set of recently-registered user contact fields so
  // UI can show name/email/phone immediately after registration before
  // the backend profile has been fetched.
  static Future<void> saveRecentRegistration({String? name, String? email, String? phone}) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        if (name != null) await prefs.setString(_keyRecentName, name);
        if (email != null) await prefs.setString(_keyRecentEmail, email);
        if (phone != null) await prefs.setString(_keyRecentPhone, phone);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          if (name != null) await s.write(key: _keyRecentName, value: name);
          if (email != null) await s.write(key: _keyRecentEmail, value: email);
          if (phone != null) await s.write(key: _keyRecentPhone, value: phone);
        } else {
          final prefs = await SharedPreferences.getInstance();
          if (name != null) await prefs.setString(_keyRecentName, name);
          if (email != null) await prefs.setString(_keyRecentEmail, email);
          if (phone != null) await prefs.setString(_keyRecentPhone, phone);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveRecentRegistration failed: $e');
    }
  }

  static Future<Map<String, String?>> getRecentRegistration() async {
    String? name;
    String? email;
    String? phone;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        name = prefs.getString(_keyRecentName);
        email = prefs.getString(_keyRecentEmail);
        phone = prefs.getString(_keyRecentPhone);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          name = await s.read(key: _keyRecentName);
          email = await s.read(key: _keyRecentEmail);
          phone = await s.read(key: _keyRecentPhone);
        } else {
          final prefs = await SharedPreferences.getInstance();
          name = prefs.getString(_keyRecentName);
          email = prefs.getString(_keyRecentEmail);
          phone = prefs.getString(_keyRecentPhone);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getRecentRegistration failed: $e');
    }
    return {'name': name, 'email': email, 'phone': phone};
  }

  // Persist a small one-time flag indicating we've shown the onboarding reminder
  // (location/profile/KYC) so we don't nag the user repeatedly.
  static Future<void> saveOnboardReminderShown(bool shown) async {
    final val = shown ? 'true' : 'false';
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyOnboardReminderShown, val);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.write(key: _keyOnboardReminderShown, value: val);
          } catch (e) {
            debugPrint('TokenStorage: secure write onboard_reminder_shown failed: $e');
            _secureAvailable = false;
          }
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyOnboardReminderShown, val);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveOnboardReminderShown failed: $e');
    }
  }

  static Future<bool?> getOnboardReminderShown() async {
    String? raw;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_keyOnboardReminderShown);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          raw = await s.read(key: _keyOnboardReminderShown);
        } else {
          final prefs = await SharedPreferences.getInstance();
          raw = prefs.getString(_keyOnboardReminderShown);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getOnboardReminderShown failed: $e');
      return null;
    }
    if (raw == null) return null;
    return raw.toLowerCase() == 'true';
  }

  // Persist a small Google profile object (as JSON) so UI can restore an
  // in-progress Google sign-in between app restarts.
  static Future<void> saveGoogleProfile(Map<String, dynamic> profile) async {
    if (profile.isEmpty) return;
    final encoded = jsonEncode(profile);
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyGoogleProfile, encoded);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          await s.write(key: _keyGoogleProfile, value: encoded);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyGoogleProfile, encoded);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveGoogleProfile failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> getGoogleProfile() async {
    String? jsonStr;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(_keyGoogleProfile);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          jsonStr = await s.read(key: _keyGoogleProfile);
        } else {
          final prefs = await SharedPreferences.getInstance();
          jsonStr = prefs.getString(_keyGoogleProfile);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getGoogleProfile failed: $e');
      return null;
    }
    if (jsonStr == null || jsonStr.isEmpty) return null;
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) return decoded;
    // If decoding yields something else, return null gracefully
    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<void> deleteGoogleProfile() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyGoogleProfile);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          await s.delete(key: _keyGoogleProfile);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_keyGoogleProfile);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: deleteGoogleProfile failed: $e');
    }
  }

  // Persist a small cached dashboard/profile object (JSON encoded wrapper)
  // Wrapper shape: { "version": 1, "timestamp": 1670000000000, "payload": { ... } }
  static Future<void> saveDashboardProfile(Map<String, dynamic> profile) async {
    if (profile.isEmpty) return;
    final wrapper = {'version': 1, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'payload': profile};
    final encoded = jsonEncode(wrapper);
    try {
      final key = await _dashboardKey(_keyDashboardProfile);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, encoded);
        // also persist legacy key for compatibility
        if (key != _keyDashboardProfile) await prefs.remove(_keyDashboardProfile);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          await s.write(key: key, value: encoded);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, encoded);
        }
        // cleanup legacy key if present
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.containsKey(_keyDashboardProfile) && key != _keyDashboardProfile) await prefs.remove(_keyDashboardProfile);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('TokenStorage: saveDashboardProfile failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> getDashboardProfile() async {
    String? jsonStr;
    try {
      final key = await _dashboardKey(_keyDashboardProfile);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(key) ?? prefs.getString(_keyDashboardProfile);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          jsonStr = await s.read(key: key) ?? await s.read(key: _keyDashboardProfile);
        } else {
          final prefs = await SharedPreferences.getInstance();
          jsonStr = prefs.getString(key) ?? prefs.getString(_keyDashboardProfile);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getDashboardProfile failed: $e');
      return null;
    }
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map && decoded['payload'] is Map) return Map<String, dynamic>.from(decoded['payload']);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('TokenStorage: parse dashboard profile failed: $e');
      return null;
    }
    return null;
  }

  static Future<void> saveDashboardData(Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final wrapper = {'version': 1, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'payload': data};
    final encoded = jsonEncode(wrapper);
    try {
      final key = await _dashboardKey(_keyDashboardData);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, encoded);
        if (key != _keyDashboardData) await prefs.remove(_keyDashboardData);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          await s.write(key: key, value: encoded);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, encoded);
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.containsKey(_keyDashboardData) && key != _keyDashboardData) await prefs.remove(_keyDashboardData);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('TokenStorage: saveDashboardData failed: $e');
    }
  }

  // Remember-me helpers: store a simple boolean and the remembered email.
  static Future<void> saveRememberMe(bool remember) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyRememberMe, remember);
      } else {
        // Use SharedPreferences for these non-sensitive UI preferences.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyRememberMe, remember);
      }
    } catch (_) {}
  }

  static Future<bool> getRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_keyRememberMe);
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveRememberedEmail(String? email) async {
    try {
      if (email == null || email.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyRememberedEmail);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRememberedEmail, email);
    } catch (_) {}
  }

  static Future<String?> getRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRememberedEmail);
    } catch (_) {
      return null;
    }
  }

  // Refresh token helpers
  static Future<void> saveRefreshToken(String refreshToken) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyRefreshToken, refreshToken);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          await s.write(key: _keyRefreshToken, value: refreshToken);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyRefreshToken, refreshToken);
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveRefreshToken failed: $e');
    }
  }

  static Future<String?> getRefreshToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_keyRefreshToken);
      }
      final s = await _getSecureStorage();
      if (s != null) {
        try {
          return await s.read(key: _keyRefreshToken);
        } catch (e) {
          debugPrint('TokenStorage: read refresh token failed: $e');
          _secureAvailable = false;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRefreshToken);
    } catch (e) {
      debugPrint('TokenStorage: getRefreshToken failed: $e');
      return null;
    }
  }

  static Future<void> deleteRefreshToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyRefreshToken);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.delete(key: _keyRefreshToken);
          } catch (e) {
            debugPrint('TokenStorage: delete refresh token failed: $e');
            _secureAvailable = false;
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyRefreshToken);
      }
    } catch (e) {
      debugPrint('TokenStorage: deleteRefreshToken failed: $e');
    }
  }

  /// Try to obtain a stable user id for namespacing caches.
  /// Order:
  /// 1. If Google profile is saved, use its 'id' or 'sub'.
  /// 2. If auth token looks like a JWT, parse payload and look for 'sub'/'id'/"userId".
  /// 3. Otherwise return null.
  static Future<String?> getUserId() async {
    try {
      final google = await getGoogleProfile();
      if (google != null) {
        final candidates = ['id', 'sub', 'userId', '_id'];
        for (final k in candidates) {
          if (google[k] != null) return google[k].toString();
        }
      }
    } catch (_) {}

    try {
      final token = await getToken();
      if (token != null && token.contains('.')) {
        final parts = token.split('.');
        if (parts.length >= 2) {
          final payload = parts[1];
          String normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
          while (normalized.length % 4 != 0) normalized += '=';
          final decoded = utf8.decode(base64Url.decode(normalized));
          final map = jsonDecode(decoded);
          if (map is Map) {
            final candidates = ['sub', 'id', 'userId', '_id'];
            for (final k in candidates) {
              if (map[k] != null) return map[k].toString();
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Read the saved KYC status string, or null if none saved.
  static Future<String?> getKycStatus() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_keyKycStatus);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            final v = await s.read(key: _keyKycStatus);
            if (v != null && v.isNotEmpty) return v;
          } catch (e) {
            debugPrint('TokenStorage: secure read kyc_status failed: $e');
            _secureAvailable = false;
          }
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          final v = prefs.getString(_keyKycStatus);
          return v;
        } catch (e) {
          debugPrint('TokenStorage: getKycStatus failed: $e');
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: getKycStatus top-level failed: $e');
    }
    return null;
  }

  /// Persist a simple KYC status string (e.g. 'pending','approved','rejected').
  /// This lets the app know when the user's submission is awaiting admin review.
  static Future<void> saveKycStatus(String status) async {
    if (status == null) return;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyKycStatus, status);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.write(key: _keyKycStatus, value: status);
          } catch (e) {
            debugPrint('TokenStorage: secure write kyc_status failed: $e');
            _secureAvailable = false;
          }
        } else {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyKycStatus, status);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('TokenStorage: saveKycStatus failed: $e');
    }
  }

  static Future<void> deleteKycStatus() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyKycStatus);
      } else {
        final s = await _getSecureStorage();
        if (s != null) {
          try {
            await s.delete(key: _keyKycStatus);
          } catch (e) {
            debugPrint('TokenStorage: secure delete kyc_status failed: $e');
            _secureAvailable = false;
          }
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_keyKycStatus);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('TokenStorage: deleteKycStatus failed: $e');
    }
  }
}
