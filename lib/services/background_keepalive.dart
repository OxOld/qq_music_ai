// 系统级后台登录态保活（Android WorkManager）
//
// App 内的 12h 定时续期只在进程存活时有效：进程被系统杀掉后就没人续期，
// 数周不开 App 连 refresh_token 链都会断（musickey 窗口一过即失效，
// 只能重新扫码）。这里注册系统级周期任务：即使 App 未运行，系统也会
// 每 12h 唤醒一次 headless isolate，用 refresh_token 续期 musickey 并
// 落盘，实现「一劳永逸」的登录保活。
//
// 注意：
// - 仅 Android 注册（车机/手机主场景）；iOS 需要额外 BGTaskScheduler
//   配置，本项目不做。
// - headless isolate 里没有 Riverpod / UI，独立用 QQAuthService +
//   QQMusicClient 完成续期并落盘（回调内可用任意 Flutter 插件）。
// - 每次仅单条轻量请求（遵守低频约定），失败静默，等 App 打开时自愈。
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'qq_auth_service.dart';
import 'qq_music_client.dart';

/// 注册任务名（headless 回调里据此识别）
const _kKeepAliveTaskName = 'qqMusicKeepAliveRefresh';
const _kKeepAliveUniqueName = 'qq-music-keepalive';

/// WorkManager 回调入口：必须是顶层函数，headless isolate 从这里启动
@pragma('vm:entry-point')
void qqKeepAliveCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await _refreshCookieInBackground();
    } catch (e) {
      debugPrint('[diag] background keepalive failed: $e');
    }
    // 始终返回成功：保活失败不是「任务失败」，下次周期还会再试
    return true;
  });
}

Future<void> _refreshCookieInBackground() async {
  final service = QQAuthService();
  final auth = await service.load();
  if (!auth.isLoggedIn) return;
  final client = QQMusicClient();
  final newCookie = await client.refreshCookie(auth);
  if (newCookie == null) return;
  final newState = QQAuthState.fromCookie(newCookie);
  // 与 App 内续期同一口径：只有 musickey 真的变了才落盘
  if (newState.isLoggedIn && newState.musickey != auth.musickey) {
    await service.save(newCookie);
  }
}

/// 注册系统级周期保活任务（App 启动时调用）。
/// 同名任务重复注册按 update 语义刷新配置；失败不影响启动流程。
Future<void> registerKeepAliveTask() async {
  try {
    await Workmanager().initialize(qqKeepAliveCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _kKeepAliveUniqueName,
      _kKeepAliveTaskName,
      // musickey 窗口约 3 天，12h 一次足够安全且低频
      frequency: const Duration(hours: 12),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint('[diag] register keepalive task failed: $e');
  }
}
