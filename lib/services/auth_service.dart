import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../api_config.dart';
import 'token_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../state/app_state_notifier.dart';
import 'dart:io';
import 'dart:async';

// Track whether GoogleSignIn.initialize() has been called to avoid calling
// it multiple times (the package requires initialize to be called exactly once).
bool _googleSignInInitialized = false;

class AuthService {
  // Internal helper: perform a POST with retries and timeouts.
  // Returns either the real http.Response or a synthetic http.Response with
  // a non-2xx status when retries exhausted.
  static Future<http.Response> _postWithRetries(
    Uri uri, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    int timeoutSeconds = 20,
    int maxAttempts = 2,
    Duration retryDelay = const Duration(milliseconds: 700),
  }) async {
    headers ??= {'Content-Type': 'application/json'};

    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ API Logger - Request (AuthService)
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [API Request] POST $uri');
    if (headers != null && headers.isNotEmpty) {
      // ignore: avoid_print
      print('│ Headers:');
      // ignore: avoid_print
      headers.forEach((k, v) => print('│   $k: $v'));
    }
    // ignore: avoid_print
    print('│ Body: ${jsonEncode(body)}');
    // ignore: avoid_print
    print(
        '└──────────────────────────────────────────────────────────────────────────────');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(Duration(seconds: timeoutSeconds));

        // ┌──────────────────────────────────────────────────────────────────────────────
        // │ API Logger - Response (AuthService)
        // └──────────────────────────────────────────────────────────────────────────────
        // ignore: avoid_print
        print(
            '┌──────────────────────────────────────────────────────────────────────────────');
        // ignore: avoid_print
        print('│ [API Response] ${resp.statusCode} $uri');
        // ignore: avoid_print
        print('│ Body: ${resp.body}');
        // ignore: avoid_print
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        return resp;
      } on TimeoutException catch (_) {
        if (attempt == maxAttempts) {
          // ignore: avoid_print
          print('│ [API Error] Request timed out for $uri');
          // ignore: avoid_print
          print(
              '└──────────────────────────────────────────────────────────────────────────────');
          return http.Response(
              jsonEncode({'message': 'Request timed out'}), 408);
        }
        await Future.delayed(retryDelay * attempt);
        continue;
      } on SocketException catch (_) {
        if (attempt == maxAttempts) {
          // ignore: avoid_print
          print('│ [API Error] Network error for $uri');
          // ignore: avoid_print
          print(
              '└──────────────────────────────────────────────────────────────────────────────');
          return http.Response(jsonEncode({'message': 'Network error'}), 599);
        }
        await Future.delayed(retryDelay * attempt);
        continue;
      } catch (e) {
        // ignore: avoid_print
        print('│ [API Error] Exception for $uri: $e');
        // ignore: avoid_print
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        return http.Response(jsonEncode({'message': e.toString()}), 500);
      }
    }
    return http.Response(jsonEncode({'message': 'Unknown network error'}), 500);
  }

  // Normalize backend role values to canonical strings used across the app.
  static String? _normalizeRoleString(dynamic raw) {
    if (raw == null) return null;
    final r = raw.toString().toLowerCase();
    if (r == 'client')
      return 'customer'; // UI label 'Client' maps to backend 'customer'
    return r;
  }

  // Persist token and role when backend returns them in various shapes.
  static Future<void> _persistTokenAndRole(dynamic body) async {
    try {
      if (body is! Map) return;

      String? token;
      dynamic roleCandidate;
      String? refreshToken;

      if (body['token'] != null) token = body['token'].toString();
      if (token == null && body['data'] is Map && body['data']['token'] != null)
        token = body['data']['token'].toString();

      // role may live at body.user.role, body.data.role or body.role
      if (body['user'] is Map && body['user']['role'] != null) {
        roleCandidate = body['user']['role'];
      } else if (body['data'] is Map && body['data']['role'] != null)
        roleCandidate = body['data']['role'];
      else if (body['role'] != null) roleCandidate = body['role'];

      final normalizedRole = _normalizeRoleString(roleCandidate);

      if (token != null) await TokenStorage.saveToken(token);
      // Persist refreshToken if backend provided one (various shapes)
      try {
        if (body['refreshToken'] != null)
          refreshToken = body['refreshToken'].toString();
        if (refreshToken == null &&
            body['data'] is Map &&
            body['data']['refreshToken'] != null) {
          refreshToken = body['data']['refreshToken'].toString();
        }
        if (refreshToken != null && refreshToken.isNotEmpty)
          await TokenStorage.saveRefreshToken(refreshToken);
      } catch (_) {}

      if (normalizedRole != null) await TokenStorage.saveRole(normalizedRole);
    } catch (e) {
      // swallow errors - token persistence is best-effort
    }
  }

  /// Registers a new user against the backend
  ///
  /// Expects the backend endpoint POST /api/auth/register to accept JSON:
  /// { name, email, password, phone }
  /// Returns a map: { success: bool, data: Map<String, dynamic> | null, error: dynamic }
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? role,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/register');

    try {
      // Ensure the email is normalized before sending
      final normalizedEmail = email.trim().toLowerCase();

      // Build the real request body (send the raw password unchanged)
      final reqBody = {
        'name': name,
        'email': normalizedEmail,
        'password': password,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
      };

      // For logging, use a redacted copy so raw password isn't printed
      if (kDebugMode) {
        try {
          final logBody = Map<String, dynamic>.from(reqBody);
          logBody['password'] = '[REDACTED]';
          debugPrint('AuthService.register payload: $logBody');
        } catch (_) {}
      }
      // Build request headers (do not send Origin from the app)
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'RijHub-Mobile/1.0',
      };
      // request headers prepared

      final resp = await _postWithRetries(uri,
          body: reqBody, headers: headers, timeoutSeconds: 20, maxAttempts: 2);

      // response received

      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

      if (status >= 200 && status < 300) {
        await _persistTokenAndRole(body);
        return {'success': true, 'data': body};
      }

      // Map synthetic network/timeout responses to friendly errors so UI shows
      // an actionable message instead of 'HTTP 599' or similar.
      if (status == 408)
        return {
          'success': false,
          'error': {'message': 'Request timed out'}
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error'}
        };

      // If backend returned 403 with empty body, provide more context in the error
      if (status == 403 && (body == null || (body is Map && body.isEmpty))) {
        final serverMsg =
            resp.headers['x-error'] ?? resp.headers['x-message'] ?? '';
        final message = serverMsg.isNotEmpty
            ? 'Forbidden: $serverMsg'
            : 'Forbidden (HTTP 403) - check backend auth/IP allowlist or server logs';
        return {
          'success': false,
          'error': {
            'message': message,
            'status': status,
            'headers': resp.headers
          }
        };
      }

      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status', 'headers': resp.headers}
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/login');

    try {
      // Normalize email client-side to ensure consistent format
      final normalizedEmail = email.trim().toLowerCase();
      final resp = await _postWithRetries(uri,
          body: {'email': normalizedEmail, 'password': password},
          timeoutSeconds: 20,
          maxAttempts: 2);

      // response received

      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

      if (status >= 200 && status < 300) {
        await _persistTokenAndRole(body);
        // After persisting, log the token stored (best-effort)
        // token persisted
        return {'success': true, 'data': body};
      }

      if (status == 408)
        return {
          'success': false,
          'error': {'message': 'Request timed out'}
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error'}
        };

      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  static Future<Map<String, dynamic>> guest() async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/guest');
    try {
      final resp = await _postWithRetries(uri,
          body: {}, timeoutSeconds: 20, maxAttempts: 2);
      if (kDebugMode) {
        try {
          debugPrint(
              'AuthService.guest -> HTTP ${resp.statusCode} ${resp.body}');
        } catch (_) {}
      }
      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

      if (status >= 200 && status < 300) {
        await _persistTokenAndRole(body);
        return {'success': true, 'data': body};
      }

      // Provide status and raw body in the returned error so callers can
      // inspect HTTP response codes (eg. 5xx) even when the server's JSON
      // body doesn't include a status field.
      if (status == 408)
        return {
          'success': false,
          'error': {
            'message': 'Request timed out',
            'status': status,
            'body': body
          }
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error', 'status': status, 'body': body}
        };

      return {
        'success': false,
        'error': (body is Map)
            ? ({
                'message': (body['message']?.toString() ?? 'HTTP $status'),
                'status': status,
                'body': body
              })
            : ({'message': 'HTTP $status', 'status': status, 'body': body})
      };
    } catch (e) {
      if (kDebugMode) {
        try {
          debugPrint('AuthService.guest -> exception: ${e.toString()}');
        } catch (_) {}
      }
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Request a password reset for the given email. This calls
  /// POST /api/auth/forgot-password and returns the server response in the
  /// standard {'success': bool, 'data'|'error': ...} shape used across AuthService.
  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/forgot-password');
    try {
      final resp = await _postWithRetries(uri,
          body: {'email': email}, timeoutSeconds: 20, maxAttempts: 2);
      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

      if (status >= 200 && status < 300) {
        return {'success': true, 'data': body};
      }

      // Map synthetic responses to a standard error shape
      if (status == 408)
        return {
          'success': false,
          'error': {'message': 'Request timed out'}
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error'}
        };

      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Send forgot-password request immediately with minimal retry/delay. This
  /// is intended for UI flows that prefer a single fast attempt and no
  /// pre-checks (avoids extra round-trips and small backoff delays).
  static Future<Map<String, dynamic>> forgotPasswordImmediate({
    required String email,
    int timeoutSeconds = 15,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/forgot-password');
    try {
      // Single attempt, short timeout
      final resp = await _postWithRetries(uri,
          body: {'email': email},
          timeoutSeconds: timeoutSeconds,
          maxAttempts: 1);
      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      if (status >= 200 && status < 300) {
        return {'success': true, 'data': body};
      }
      if (status == 408)
        return {
          'success': false,
          'error': {'message': 'Request timed out'}
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error'}
        };
      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Check whether an email address exists on the platform.
  ///
  /// IMPORTANT: This method assumes the backend exposes a safe endpoint
  /// `POST /api/auth/check-email` which accepts `{ email }` and returns a
  /// JSON body like `{ exists: true }` when the email is registered, or
  /// `{ exists: false }` when it is not. If your backend does not provide
  /// such an endpoint this method will fail; adding this endpoint server-side
  /// is required to avoid email enumeration risks.
  static Future<Map<String, dynamic>> checkEmailExists({
    required String email,
  }) async {
    final uri = Uri.parse('$API_BASE_URL/api/auth/check-email');
    try {
      final resp = await _postWithRetries(uri,
          body: {'email': email}, timeoutSeconds: 15, maxAttempts: 2);
      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

      if (status >= 200 && status < 300) {
        return {'success': true, 'data': body};
      }

      if (status == 408)
        return {
          'success': false,
          'error': {'message': 'Request timed out'}
        };
      if (status == 599)
        return {
          'success': false,
          'error': {'message': 'Network error'}
        };

      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Sign in with Google, send tokens to backend and persist returned JWT if any.
  /// Returns {'success': bool, 'data': <backend response> , 'profile': {name,email,photo}} on success.
  /// [role] - Optional role to assign during signup (e.g., 'artisan' or 'customer').
  static Future<Map<String, dynamic>> signInWithGoogle({String? role}) async {
    // ┌──────────────────────────────────────────────────────────────────────────────
    // │ Google Sign-In - Start
    // └──────────────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [Google Sign-In] Starting Google authentication...');

    try {
      final googleSignIn = GoogleSignIn.instance;

      // Initialize the plugin once per app lifecycle.
      if (!_googleSignInInitialized) {
        // ignore: avoid_print
        print('│ [Google Sign-In] Initializing GoogleSignIn plugin...');

        // On Android, serverClientId is REQUIRED to get an ID token.
        // This should be the Web Client ID from Google Cloud Console.
        final serverClientId = GOOGLE_WEB_CLIENT_ID;
        // ignore: avoid_print
        print(
            '│ [Google Sign-In] serverClientId: ${serverClientId ?? "NOT SET - will fail on Android!"}');

        // google_sign_in v7 uses named parameters for initialize()
        await googleSignIn.initialize(serverClientId: serverClientId);
        _googleSignInInitialized = true;
        // ignore: avoid_print
        print('│ [Google Sign-In] Plugin initialized successfully');
      }

      GoogleSignInAccount account;
      try {
        // `authenticate` starts an interactive sign-in and returns an account.
        // ignore: avoid_print
        print('│ [Google Sign-In] Calling authenticate()...');
        account = await googleSignIn.authenticate();
        // ignore: avoid_print
        print(
            '│ [Google Sign-In] authenticate() returned account: ${account.email}');
      } on GoogleSignInException catch (e) {
        // User cancelled or other auth issues.
        // ignore: avoid_print
        print('│ [Google Sign-In] GoogleSignInException: code=${e.code}');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted ||
            e.code == GoogleSignInExceptionCode.uiUnavailable) {
          return {
            'success': false,
            'error': {'message': 'Google sign-in cancelled'}
          };
        }
        rethrow;
      }

      final auth = account.authentication;
      final idToken = auth.idToken;
      // ignore: avoid_print
      print(
          '│ [Google Sign-In] Got authentication, idToken present: ${idToken != null}');

      if (idToken == null) {
        // ignore: avoid_print
        print(
            '│ [Google Sign-In] ERROR: idToken is null! Check serverClientId configuration.');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        return {
          'success': false,
          'error': {
            'message':
                'Missing Google idToken - serverClientId may not be configured'
          }
        };
      }

      // ignore: avoid_print
      print('│ [Google Sign-In] Sending idToken to backend...');
      final uri = Uri.parse('$API_BASE_URL/api/auth/oauth/google');
      final resp = await _postWithRetries(uri,
          body: {
            'idToken': idToken,
            if (role != null) 'role': role,
          },
          timeoutSeconds: 20,
          maxAttempts: 2);

      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      // ignore: avoid_print
      print('│ [Google Sign-In] Backend response: HTTP $status');

      if (status >= 200 && status < 300) {
        await _persistTokenAndRole(body);
        // ignore: avoid_print
        print('│ [Google Sign-In] SUCCESS - Token persisted');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        return {
          'success': true,
          'data': body,
          'profile': {
            'name': account.displayName,
            'email': account.email,
            'photo': account.photoUrl,
          }
        };
      }

      // ignore: avoid_print
      print('│ [Google Sign-In] FAILED - Backend returned error');
      print(
          '└──────────────────────────────────────────────────────────────────────────────');
      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('│ [Google Sign-In] EXCEPTION: $e');
      print('│ [Google Sign-In] Stack: $stackTrace');
      print(
          '└──────────────────────────────────────────────────────────────────────────────');
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Sign in with Apple, send tokens to backend and persist returned JWT if any.
  /// Returns {'success': bool, 'data': <backend response>, 'profile': {name, email}} on success.
  /// [role] - Optional role to assign during signup (e.g., 'artisan' or 'customer').
  static Future<Map<String, dynamic>> signInWithApple({String? role}) async {
    // Import required for Apple Sign-In
    // ignore: avoid_print
    print(
        '┌──────────────────────────────────────────────────────────────────────────────');
    // ignore: avoid_print
    print('│ [Apple Sign-In] Starting Apple authentication...');

    try {
      // Generate a cryptographically secure random nonce
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      // ignore: avoid_print
      print('│ [Apple Sign-In] Requesting Apple credentials...');

      // Request credentials from Apple
      final credential = await _getAppleCredential(hashedNonce);

      // ignore: avoid_print
      print(
          '│ [Apple Sign-In] Got credential, identityToken present: ${credential.identityToken != null}');

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        // ignore: avoid_print
        print('│ [Apple Sign-In] ERROR: identityToken is null!');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        return {
          'success': false,
          'error': {'message': 'Missing Apple identityToken'}
        };
      }

      // Build user name from Apple credential (only provided on first sign-in)
      String? displayName;
      if (credential.givenName != null || credential.familyName != null) {
        displayName =
            '${credential.givenName ?? ''} ${credential.familyName ?? ''}'
                .trim();
      }

      // Send to backend
      // ignore: avoid_print
      print('│ [Apple Sign-In] Sending identityToken to backend...');
      final uri = Uri.parse('$API_BASE_URL/api/auth/oauth/apple');
      // For mobile apps, use identity-token flow (NOT authorization-code flow)
      // We send: identityToken + raw nonce (backend will hash and verify)
      final resp = await _postWithRetries(uri,
          body: {
            'identityToken': identityToken,
            'nonce': rawNonce, // Send raw nonce for backend verification
            if (displayName != null && displayName.isNotEmpty)
              'name': displayName,
            if (credential.email != null) 'email': credential.email,
            if (role != null) 'role': role,
          },
          timeoutSeconds: 20,
          maxAttempts: 2);

      final status = resp.statusCode;
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      // ignore: avoid_print
      print('│ [Apple Sign-In] Backend response: HTTP $status');

      if (status >= 200 && status < 300) {
        await _persistTokenAndRole(body);
        // ignore: avoid_print
        print('│ [Apple Sign-In] SUCCESS - Token persisted');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');

        return {
          'success': true,
          'data': body,
          'profile': {
            'name': displayName,
            'email': credential.email,
          }
        };
      }

      // ignore: avoid_print
      print('│ [Apple Sign-In] FAILED - Backend returned error');
      print(
          '└──────────────────────────────────────────────────────────────────────────────');
      return {
        'success': false,
        'error': body ?? {'message': 'HTTP $status'}
      };
    } catch (e, stackTrace) {
      // Handle user cancellation gracefully
      if (e.toString().contains('canceled') ||
          e.toString().contains('AuthorizationErrorCode.canceled')) {
        // ignore: avoid_print
        print('│ [Apple Sign-In] User cancelled');
        print(
            '└──────────────────────────────────────────────────────────────────────────────');
        return {
          'success': false,
          'error': {'message': 'Apple sign-in cancelled'}
        };
      }

      // ignore: avoid_print
      print('│ [Apple Sign-In] EXCEPTION: $e');
      print('│ [Apple Sign-In] Stack: $stackTrace');
      print(
          '└──────────────────────────────────────────────────────────────────────────────');
      return {
        'success': false,
        'error': {'message': e.toString()}
      };
    }
  }

  /// Get Apple ID credential using the sign_in_with_apple package
  static Future<AuthorizationCredentialAppleID> _getAppleCredential(
      String hashedNonce) async {
    return await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
  }

  /// Generates a cryptographically secure random nonce
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// Returns the SHA256 hash of [input] as a hex string
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Clears persisted authentication (token + role) and signs out Google.
  static Future<void> logout() async {
    try {
      await TokenStorage.deleteToken();
      await TokenStorage.deleteRole();
      // Also remove any cached Google profile when logging out
      try {
        await TokenStorage.deleteGoogleProfile();
      } catch (_) {}
    } catch (_) {}

    // Clear in-memory app state to immediately update route guards
    try {
      AppStateNotifier.instance.clearAuth();
    } catch (_) {}

    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  /// Try to refresh an access token using a refresh token. Returns the
  /// refreshed payload (map) that contains a new token or null if refresh
  /// isn't supported or failed. This calls POST /api/auth/refresh which may
  /// not be implemented on the server; the method handles failures gracefully.
  static Future<Map<String, dynamic>?> tryRefreshToken(
      String refreshToken) async {
    try {
      final uri = Uri.parse('$API_BASE_URL/api/auth/refresh');
      final resp = await _postWithRetries(uri,
          body: {'refreshToken': refreshToken},
          timeoutSeconds: 15,
          maxAttempts: 2);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        return body as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }
}
