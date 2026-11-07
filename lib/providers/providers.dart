import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/llm_service.dart';
import '../services/match_service.dart';
import '../services/player_service.dart';
import '../services/qq_auth_service.dart';
import '../services/qq_music_client.dart';
import '../services/settings_service.dart';

/// 设置服务
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// LLM 服务
final llmServiceProvider = Provider<LlmService>((ref) {
  return LlmService();
});

/// QQ 音乐客户端
final qqMusicClientProvider = Provider<QQMusicClient>((ref) {
  return QQMusicClient();
});

/// QQ 音乐登录态服务
final qqAuthServiceProvider = Provider<QQAuthService>((ref) {
  return QQAuthService();
});

/// 匹配服务
final matchServiceProvider = Provider<MatchService>((ref) {
  return MatchService(client: ref.watch(qqMusicClientProvider));
});

/// 播放器服务（全局单例，与系统媒体通知共用）
final playerServiceProvider = Provider<PlayerService>((ref) {
  return PlayerService.instance;
});

/// 当前 LLM 配置（异步加载，可刷新）
final llmConfigProvider = FutureProvider<LlmConfig>((ref) async {
  final service = ref.watch(settingsServiceProvider);
  return service.load();
});

/// QQ 音乐登录态（可变，登录/登出后自动更新 UI）
class QQAuthNotifier extends StateNotifier<QQAuthState> {
  QQAuthNotifier(this._service) : super(const QQAuthState()) {
    _load();
  }

  final QQAuthService _service;

  Future<void> _load() async {
    state = await _service.load();
  }

  Future<void> saveCookie(String cookie) async {
    await _service.save(cookie);
    state = QQAuthState.fromCookie(cookie);
  }

  Future<void> logout() async {
    await _service.clear();
    state = const QQAuthState();
  }
}

final qqAuthProvider =
    StateNotifierProvider<QQAuthNotifier, QQAuthState>((ref) {
  return QQAuthNotifier(ref.watch(qqAuthServiceProvider));
});
