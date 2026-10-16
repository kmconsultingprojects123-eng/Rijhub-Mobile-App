import 'token_storage.dart';
import '../flutter_flow/nav/nav.dart';

/// Compatibility wrapper: delegate to TokenStorage which implements secure
/// storage on native platforms and SharedPreferences on web.
class AuthStorage {
  static Future<void> saveToken(String token) async => await TokenStorage.saveToken(token);
  static Future<String?> getToken() async => await TokenStorage.getToken();
  static Future<void> saveRole(String role) async => await TokenStorage.saveRole(role);
  static Future<String?> getRole() async => await TokenStorage.getRole();
  static Future<void> clear() async {
    await TokenStorage.deleteToken();
    await TokenStorage.deleteRole();
    try { await TokenStorage.deleteGoogleProfile(); } catch (_) {}
    try { AppStateNotifier.instance.clearAuth(); } catch (_) {}
  }
}
