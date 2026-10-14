import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ids.dart';

/// Tokens and device secrets live only in Keychain / Android Keystore / Windows
/// credential storage. Nothing sensitive goes to shared preferences.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _access = 'mk.access';
  static const _refresh = 'mk.refresh';
  static const _deviceId = 'mk.device_id';

  Future<String?> read(String key) => _s.read(key: key);
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);

  Future<String?> get accessToken => read(_access);
  Future<String?> get refreshToken => read(_refresh);

  Future<void> saveTokens({required String access, String? refresh}) async {
    await write(_access, access);
    if (refresh != null) await write(_refresh, refresh);
  }

  Future<void> clearTokens() async {
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
  }

  /// Stable random install id (not a hardware identifier).
  Future<String> deviceId() async {
    final existing = await read(_deviceId);
    if (existing != null) return existing;
    final id = newUuid();
    await write(_deviceId, id);
    return id;
  }
}
