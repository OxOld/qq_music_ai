import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import 'app_dialog.dart';

/// 「登录已过期」引导：确认后打开扫码登录页。
///
/// 供各写操作在登录态彻底失效（静默续期未能自动恢复）时统一调用，
/// 与播放链路的手动引导保持一致的交互。
Future<void> showReloginDialog(
  BuildContext context, {
  String message = '操作需要有效的登录态，自动续期未能恢复。\n重新扫码登录后即可继续。',
}) async {
  final relogin = await showAppConfirmDialog(
    context,
    title: '登录已过期',
    message: message,
    confirmLabel: '重新登录',
    icon: Icons.login_rounded,
  );
  if (relogin && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }
}
