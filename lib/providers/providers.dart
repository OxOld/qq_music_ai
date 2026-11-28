import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/llm_service.dart';
import '../services/match_service.dart';
import '../services/player_service.dart';
import '../services/prompt_service.dart';
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

/// AI 提示词服务（可编辑前缀，与固定规则段运行时拼接）
final promptServiceProvider = Provider<PromptService>((ref) {
  return PromptService();
});

/// 当前提示词配置（异步加载，保存后 invalidate 刷新）
final promptConfigProvider = FutureProvider<PromptConfig>((ref) async {
  final service = ref.watch(promptServiceProvider);
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
  Future<void>? _refreshInFlight;
  DateTime _lastAutoRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _load() async {
    state = await _service.load();
    _scheduleRefresh();
    // 加载后立即尝试续期一次（数天未开 App 的场景在启动时就补上）
    unawaited(refresh());
  }

  /// 静默续期登录态；成功则更新 state 并持久化。
  /// 并发调用共享同一在途请求：避免重复请求，也避免两个响应乱序
  /// 把较旧的 Cookie 覆盖回去。
  Future<void> refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _doRefresh() async {
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

  /// 用（必要时自动续期的）登录态执行需要鉴权的操作。
  ///
  /// 写接口对登录态要求严格，key 滑动过期后删除/添加会直接失败
  /// （表现为「音乐还能播，管理歌单却报错」）。这里先按当前登录态
  /// 执行；遇到登录态类失败时静默续期一次，key 确有更新才重试
  /// （避免对网络抖动导致的失败做重复写入）；续期不可用（微信登录 /
  /// refresh_token 失效）则原样抛出，由调用方引导重新登录。
  Future<T> runWithFreshAuth<T>(
    Future<T> Function(QQAuthState auth) action,
  ) async {
    try {
      return await action(state);
    } on QQMusicAuthExpiredException {
      final oldKey = state.musickey;
      await refresh();
      if (!state.isLoggedIn || state.musickey == oldKey) rethrow;
      return await action(state);
    }
  }

  /// 回到前台时补一次续期（进程被系统冻结时 12h 定时器不会走）。
  /// 30 分钟内不重复请求，频繁前后台切换也不轰炸。
  void refreshOnResume() {
    if (!state.isLoggedIn) return;
    final now = DateTime.now();
    if (now.difference(_lastAutoRefresh) < const Duration(minutes: 30)) return;
    _lastAutoRefresh = now;
    unawaited(refresh());
  }

  /// 每 12 小时续期一次（musickey 有效期约 3 天，取一半周期足够安全）
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!state.isLoggedIn) return;
    _refreshTimer = Timer.periodic(const Duration(hours: 12), (_) {
      _lastAutoRefresh = DateTime.now();
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

final qqAuthProvider = StateNotifierProvider<QQAuthNotifier, QQAuthState>((
  ref,
) {
  return QQAuthNotifier(
    ref.watch(qqAuthServiceProvider),
    client: ref.watch(qqMusicClientProvider),
  );
});
