import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'qq_music_client.dart';

/// QQ 音乐登录态持久化服务
class QQAuthService {
  static const _storage = FlutterSecureStorage(
    // 模拟器 / 重装后 Keystore 可能损坏导致读写永久失败；
    // resetOnError 会清掉损坏数据并重建密钥，避免"永远未登录"。
    aOptions: AndroidOptions(resetOnError: true),
  );
  static const _kCookie = 'qq_cookie';

  Future<QQAuthState> load() async {
    try {
      final cookie = await _storage.read(key: _kCookie) ?? '';
      return QQAuthState.fromCookie(cookie);
    } catch (_) {
      return const QQAuthState();
    }
  }

  Future<void> save(String cookie) async {
    await _storage.write(key: _kCookie, value: cookie);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kCookie);
  }
}
