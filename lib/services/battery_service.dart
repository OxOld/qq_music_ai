import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_dialog.dart';

/// 省电策略豁免（后台连续播放）
///
/// 国产 ROM（MIUI/HyperOS 等）对后台应用约 10 分钟后断网，前台服务也拦不住，
/// 表现为熄屏两三首歌后连播停止。系统级解法是加入电池优化豁免
/// （即 MIUI 省电策略「不限制」），App 主动拉起系统授权弹窗引导用户确认。
class BatteryService {
  static const _channel = MethodChannel('qq_music_ai/battery');

  /// SharedPreferences 标记：授权弹窗已询问过（每次安装只自动问一次）
  static const _askedKey = 'battery_opt_asked';

  static bool _prompting = false;

  /// 当前是否已在电池优化豁免名单中（省电策略=不限制）
  ///
  /// 平台不支持或通道异常时返回 true：不影响使用，也不再打扰
  static Future<bool> isIgnoring() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoring') ?? false;
    } catch (_) {
      return true;
    }
  }

  /// 拉起系统授权弹窗（用户在系统窗里确认后生效）
  static Future<void> requestIgnore() async {
    try {
      await _channel.invokeMethod('requestIgnore');
    } catch (_) {}
  }

  /// 播放前调用：未豁免且未询问过时，弹说明窗引导授权。
  /// 只问一次；拒绝后不再打扰，可到 设置 → 后台播放 手动开启。
  static Future<void> maybePromptOnPlay(BuildContext context) async {
    if (_prompting) return;
    _prompting = true;
    try {
      if (await isIgnoring()) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;
      await prefs.setBool(_askedKey, true);
      if (!context.mounted) return;
      final ok = await showAppConfirmDialog(
        context,
        title: '允许后台播放？',
        message:
            '熄屏后系统可能限制应用联网，导致歌曲无法自动连播。\n'
            '建议允许后台运行（省电策略「不限制」），获得连续的听歌体验。',
        confirmLabel: '去设置',
        cancelLabel: '暂不',
        icon: Icons.bolt_rounded,
      );
      if (ok) await requestIgnore();
    } finally {
      _prompting = false;
    }
  }
}
