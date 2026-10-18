import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the signed-in person's tokens live between launches.
abstract interface class TokenStore {
  Future<String?> access();
  Future<String?> refresh();
  Future<void> save({required String access, required String refresh});
  Future<void> clear();
}

/// The phone's keychain (iOS) or keystore-backed storage (Android). Read
/// once, then kept in memory.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'rijhub.access_token';
  static const _refreshKey = 'rijhub.refresh_token';

  final FlutterSecureStorage _storage;
  bool _loaded = false;
  String? _access;
  String? _refresh;

  Future<void> _load() async {
    if (_loaded) return;
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } on Object {
      // Unreadable (restored from another device's backup): signed out.
      _access = _refresh = null;
    }
    _loaded = true;
  }

  @override
  Future<String?> access() async {
    await _load();
    return _access;
  }

  @override
  Future<String?> refresh() async {
    await _load();
    return _refresh;
  }

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    _loaded = true;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  @override
  Future<void> clear() async {
    _access = _refresh = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// Tokens kept only while the app runs: for tests.
class MemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> access() async => _access;

  @override
  Future<String?> refresh() async => _refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async => _access = _refresh = null;
}
