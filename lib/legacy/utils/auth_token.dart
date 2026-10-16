import 'dart:convert';

/// Small helpers to inspect a JWT token client-side.
/// These avoid adding another package dependency.

int? jwtExp(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final map = json.decode(decoded) as Map<String, dynamic>;
    if (map.containsKey('exp')) {
      final exp = map['exp'];
      if (exp is int) return exp;
      if (exp is double) return exp.toInt();
      if (exp is String) return int.tryParse(exp);
    }
  } catch (_) {}
  return null;
}

bool isTokenExpired(String? token, {int skewSeconds = 30}) {
  if (token == null || token.isEmpty) return true;
  final exp = jwtExp(token);
  if (exp == null) return true;
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return (exp - skewSeconds) <= now;
}

