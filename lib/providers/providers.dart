import 'dart:async';

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
///
/// musickey（qm_keyst）是滑动窗口有效期：App 数天不打开，窗口一过即失效，
/// 表现为「歌单列表正常、VIP 歌曲播放提示需会员」。这里做两件事：
/// 1. 启动加载后立即静默续期一次（QQ 登录且有 refresh_token 才可行）；
/// 2. 每 12 小时定时续期，保证后台常驻时窗口不中断。
/// 续期失败（非 QQ 登录 / key 已彻底过期）不打扰用户，
/// 由 getPlayUrl 抛出的 QQMusicAuthExpiredException 引导重新登录。
class QQAuthNotifier extends StateNotifier<QQAuthState> {
  QQAuthNotifier(this._service, {QQMusicClient? client})
    : _client = client,
      super(const QQAuthState()) {
    _load();
  }

  final QQAuthService _service;
  final QQMusicClient? _client;
  Timer? _refreshTimer;

  Future<void> _load() async {
    state = await _service.load();
    _scheduleRefresh();
    // 加载后立即尝试续期一次（数天未开 App 的场景在启动时就补上）
    unawaited(refresh());
  }

  /// 静默续期登录态；成功则更新 state 并持久化
  Future<void> refresh() async {
    final client = _client;
    if (client == null || !state.isLoggedIn) return;
    try {
      final newCookie = await client.refreshCookie(state);
      if (newCookie == null) return;
      final newState = QQAuthState.fromCookie(newCookie);
      if (!newState.isLoggedIn) return;
      // 只有 musickey 真的变了才落盘，避免无谓写入
      if (newState.musickey != state.musickey) {
        await _service.save(newCookie);
        state = newState;
      }
    } catch (_) {
      // 静默失败：不打扰用户，等真正过期时由异常引导重登
    }
  }

  /// 每 12 小时续期一次（musickey 有效期约 3 天，取一半周期足够安全）
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!state.isLoggedIn) return;
    _refreshTimer = Timer.periodic(const Duration(hours: 12), (_) {
      unawaited(refresh());
    });
  }

  Future<void> saveCookie(String cookie) async {
    await _service.save(cookie);
    state = QQAuthState.fromCookie(cookie);
    _scheduleRefresh();
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    await _service.clear();
    state = const QQAuthState();
  }
}

final qqAuthProvider =
    StateNotifierProvider<QQAuthNotifier, QQAuthState>((ref) {
  return QQAuthNotifier(
    ref.watch(qqAuthServiceProvider),
    client: ref.watch(qqMusicClientProvider),
  );
});
