import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';

/// Who is using the app. People can explore as guests; they only sign in
/// when an action needs an account (booking, posting a job, quoting).
/// Screens watch this; the router reads [hasOnboarded] on each navigation
/// but isn't refreshed by changes, so screens navigate after the change
/// they cause.
class SessionController extends ChangeNotifier {
  SessionController({
    required SharedPreferences prefs,
    required AuthRepository auth,
  })  : _prefs = prefs,
        _auth = auth;

  // Mock sessions only hold the profile. Real tokens will live in secure
  // storage once the new backend issues them.
  static const _userKey = 'session.user';
  static const _guestRoleKey = 'session.guestRole';
  static const _onboardedKey = 'session.onboarded';
  static const _areaKey = 'session.area';
  static const _themeKey = 'session.theme';
  static const _guestTradesKey = 'session.guestTrades';
  static const _pushAskedKey = 'session.pushAsked';
  static const _readAloudKey = 'session.readAloud';

  final SharedPreferences _prefs;
  final AuthRepository _auth;
  AppUser? _user;
  UserRole _guestRole = UserRole.client;
  bool _onboarded = false;
  String? _area;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isGuest => _user == null;

  /// The side of the app to show: the signed-in user's role, or the one a
  /// guest picked on the welcome screen.
  UserRole get role => _user?.role ?? _guestRole;

  /// False until someone picks a path on the welcome screen or signs in.
  bool get hasOnboarded => _onboarded;

  /// The trades an artisan picked before signing up, so their jobs come
  /// first and sign-up doesn't ask again.
  List<String> get guestTrades =>
      _prefs.getStringList(_guestTradesKey) ?? const [];

  /// Notifications have been offered once already, so they aren't again.
  bool get pushAsked => _prefs.getBool(_pushAskedKey) ?? false;

  Future<void> markPushAsked() => _prefs.setBool(_pushAskedKey, true);

  /// Whether the Ask chat reads its messages aloud, once the person has
  /// chosen with its speaker button; null until then.
  bool? get readAloud => _prefs.getBool(_readAloudKey);

  Future<void> setReadAloud(bool on) async {
    await _prefs.setBool(_readAloudKey, on);
    notifyListeners();
  }

  /// The trades jobs are shown for: the account's, else those picked
  /// while looking around.
  List<String> get tradeIds => _user?.tradeIds ?? guestTrades;

  Future<void> setGuestTrades(List<String> tradeIds) async {
    await _prefs.setStringList(_guestTradesKey, tradeIds);
    notifyListeners();
  }

  /// The neighbourhood "near you" results use: the one picked on this
  /// device, else the signed-in user's. Null means all of Abuja.
  String? get area => _area ?? _user?.homeArea;

  /// Light, dark, or as the phone is set (the default).
  ThemeMode get themeMode => switch (_saved<String>(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  /// Loads saved state. Local and fast, so it runs before the first frame.
  /// A value this version can't read (left by another one) is dropped
  /// rather than stopping the app from starting.
  void restore() {
    _onboarded = _saved<bool>(_onboardedKey) ?? false;
    _area = _saved<String>(_areaKey);
    final role = _saved<String>(_guestRoleKey);
    if (role != null) {
      final known = UserRole.values.asNameMap()[role];
      if (known == null) _prefs.remove(_guestRoleKey);
      _guestRole = known ?? UserRole.client;
    }
    final raw = _saved<String>(_userKey);
    if (raw == null) return;
    final AppUser user;
    try {
      user = AppUser.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      _prefs.remove(_userKey);
      return;
    }
    _user = user;
    _auth.useAccount(user);
  }

  /// The value saved under [key], or null if there is none or it isn't a
  /// [T], in which case it is removed.
  T? _saved<T extends Object>(String key) {
    final value = _prefs.get(key);
    if (value is T) return value;
    if (value != null) _prefs.remove(key);
    return null;
  }

  /// Enters the app without an account, as a client or an artisan.
  Future<void> continueAsGuest(UserRole role) async {
    _guestRole = role;
    _onboarded = true;
    await _prefs.setString(_guestRoleKey, role.name);
    await _prefs.setBool(_onboardedKey, true);
    notifyListeners();
  }

  Future<void> signIn(AppUser user) async {
    _user = user;
    _auth.useAccount(user);
    _guestRole = user.role;
    _onboarded = true;
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
    await _prefs.setString(_guestRoleKey, user.role.name);
    await _prefs.setBool(_onboardedKey, true);
    notifyListeners();
  }

  /// Remembers the area someone picked. It stays on this device, through
  /// signing in and out, like the role.
  Future<void> setArea(String area) async {
    _area = area;
    await _prefs.setString(_areaKey, area);
    notifyListeners();
  }

  /// Signs out but keeps the person in the app as a guest of the same role.
  ///
  /// The device signs out at once, connection or not. Ending the session on
  /// the server comes after, and a failure there doesn't undo it.
  Future<void> signOut() async {
    if (_user == null) return;
    _user = null;
    await _prefs.remove(_userKey);
    notifyListeners();
    try {
      await _auth.signOut();
    } on AuthException {
      // Offline, or already ended on the server: either way the device is
      // signed out, which is what the person asked for.
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'session',
          context: ErrorDescription('while ending the session on the server'),
        ),
      );
    }
  }

  /// Forgets everything, including onboarding. For QA launches.
  Future<void> reset() async {
    _user = null;
    _guestRole = UserRole.client;
    _onboarded = false;
    _area = null;
    await _prefs.remove(_userKey);
    await _prefs.remove(_guestRoleKey);
    await _prefs.remove(_onboardedKey);
    await _prefs.remove(_areaKey);
    await _prefs.remove(_guestTradesKey);
    notifyListeners();
  }
}

/// State for a sign-in that is in progress: the phone number and the
/// pending code. One flow serves new and returning users, because a phone
/// number and its code are all either needs. The role comes from the side
/// of the app the person is using, so it is never asked for.
class AuthFlowController extends ChangeNotifier {
  AuthFlowController({
    required AuthRepository auth,
    required SessionController session,
  })  : _auth = auth,
        _session = session;

  final AuthRepository _auth;
  final SessionController _session;

  /// How long a sent code stays worth coming back to.
  static const resumeWindow = Duration(minutes: 10);

  /// The 10 national digits, for example "8031234567".
  String? phone;
  OtpChallenge? challenge;
  DateTime? _codeSentAt;

  /// Digits typed so far, kept if the sheet is closed and reopened.
  String draftCode = '';

  /// Counts sign-in attempts. A request that finishes after its attempt
  /// was reset or replaced is ignored, so a slow reply can't bring back an
  /// old number or code.
  int _attempt = 0;

  /// The number is verified but has no account yet, so the next step is
  /// the person's details.
  bool needsDetails = false;

  String? get phoneDisplay =>
      phone == null ? null : NigerianPhone.display(phone!);

  /// The role a new account will get.
  UserRole get role => _session.role;

  /// Where a reopened sheet should start.
  AuthStep get resumeStep {
    if (phone != null && needsDetails) return AuthStep.details;
    final sentAt = _codeSentAt;
    if (phone != null &&
        challenge != null &&
        sentAt != null &&
        DateTime.now().difference(sentAt) < resumeWindow) {
      return AuthStep.code;
    }
    return AuthStep.phone;
  }

  /// Call when the sign-in sheet opens: keeps a recent attempt so people
  /// who left to read their SMS carry on where they were.
  void begin() {
    if (resumeStep == AuthStep.phone) reset();
  }

  /// Starts over, for "Change number" or after finishing.
  void reset() {
    _attempt++;
    phone = null;
    challenge = null;
    _codeSentAt = null;
    draftCode = '';
    needsDetails = false;
  }

  /// Restores a code that was sent earlier (for QA launches).
  void restoreChallenge(String nationalNumber, OtpChallenge pending) {
    phone = nationalNumber;
    challenge = pending;
    _codeSentAt = DateTime.now();
  }

  /// Sends a code; null once it's on its way. When the phone confirmed the
  /// number by itself (Android can), there's nothing to type: true when that
  /// signed the person in, false when they go on to add their details.
  Future<bool?> sendCode(
    String nationalNumber, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    final attempt = ++_attempt;
    phone = nationalNumber;
    final sent = await _auth.requestCode(
      NigerianPhone.toE164(nationalNumber),
      channel: channel,
    );
    if (attempt != _attempt) return null;
    challenge = sent;
    _codeSentAt = DateTime.now();
    draftCode = '';
    needsDetails = false;
    notifyListeners();
    return sent.verified ? verify('') : null;
  }

  Future<bool?> resend({OtpChannel? channel}) => sendCode(
        phone!,
        channel: channel ?? challenge?.channel ?? OtpChannel.sms,
      );

  /// Signs in and returns true when the number already has an account.
  /// Returns false when the person still needs to add their details, and
  /// null when the attempt was reset or a new code sent while checking, in
  /// which case nothing changes.
  Future<bool?> verify(String code) async {
    final pending = challenge!;
    final result = await _auth.verifyCode(pending, code);
    if (!identical(pending, challenge)) return null;
    if (result.user == null) {
      needsDetails = true;
      notifyListeners();
      return false;
    }
    await _session.signIn(result.user!);
    reset();
    return true;
  }

  Future<void> createAccount({
    required String fullName,
    String? email,
    List<String> tradeIds = const [],
  }) async {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final user = await _auth.createAccount(
      phone: NigerianPhone.toE164(phone!),
      role: role,
      firstName: parts.first,
      lastName: parts.skip(1).join(' '),
      email: email,
      // The area they picked while exploring, so nothing changes under
      // them; null keeps all of Abuja.
      area: _session.area,
      // Trades picked while looking around count, unless new ones are given.
      tradeIds: tradeIds.isEmpty && role == UserRole.artisan
          ? _session.guestTrades
          : tradeIds,
    );
    await _session.signIn(user);
    reset();
  }
}

/// The steps of the sign-in sheet.
enum AuthStep { phone, code, details }
