import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// QQ 音乐登录页：内嵌 WebView 扫码登录，登录后抓取 Cookie
///
/// 支持两种方式：
/// 1. WebView 扫码登录 → 自动抓取 Cookie
/// 2. 手动粘贴 Cookie（兜底，用于自动抓取失败时）
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _cookieController = TextEditingController();
  InAppWebViewController? _webController;
  bool _saving = false;

  /// 从 WebView 抓取 Cookie。
  /// QQ 音乐的登录态（uin/skey）在 .qq.com 域，musickey 在 .y.qq.com 域，
  /// 因此需要抓多个域再合并。
  Future<String> _grabCookie() async {
    final cookieManager = CookieManager.instance();
    final merged = <String, String>{};
    for (final domain in [
      'https://qq.com/',
      'https://y.qq.com/',
      'https://c.y.qq.com/',
    ]) {
      try {
        final cookies =
            await cookieManager.getCookies(url: WebUri(domain));
        for (final c in cookies) {
          merged[c.name] = c.value;
        }
      } catch (_) {}
    }
    final parts = merged.entries.map((e) => '${e.key}=${e.value}').toList();
    return parts.join('; ');
  }

  Future<void> _saveCookie(String cookie) async {
    final auth = QQAuthState.fromCookie(cookie);
    if (!auth.isLoggedIn) return;
    await ref.read(qqAuthProvider.notifier).saveCookie(cookie);
  }

  Future<void> _finishLogin() async {
    if (_saving) return;
    setState(() => _saving = true);

    // 1. 先尝试自动抓取
    var ok = false;
    final autoCookie = await _grabCookie();
    if (QQAuthState.fromCookie(autoCookie).isLoggedIn) {
      await _saveCookie(autoCookie);
      ok = true;
    }

    // 2. 兜底：手动粘贴的 Cookie
    if (!ok) {
      final manual = _cookieController.text.trim();
      if (manual.isNotEmpty) {
        final auth = QQAuthState.fromCookie(manual);
        if (auth.isLoggedIn) {
          await _saveCookie(manual);
          ok = true;
        }
      }
    }

    if (!context.mounted) return;
    setState(() => _saving = false);
    if (ok) {
      AppToast.show(context, '登录成功', success: true);
      Navigator.of(context).pop();
    } else {
      AppToast.show(
        context,
        '未检测到登录态。请先扫码登录，或手动粘贴 Cookie',
      );
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '登录 QQ 音乐',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: AppColors.bg,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _finishLogin,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppColors.brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              child: Text(
                _saving ? '检测中…' : '完成登录',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ---------- 提示条 ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.brandSoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: AppColors.brandDeep, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '在下方页面扫码登录（QQ 或微信），成功后点右上角「完成登录」',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---------- 清理登录状态（切换账号用） ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: const Text('清理登录状态',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      content: const Text(
                          '将清除 WebView Cookie 与本机保存的登录态，'
                          '用于切换 QQ 账号。确定吗？',
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: AppColors.textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('取消',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('清理',
                              style: TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !mounted) return;
                  await CookieManager.instance().deleteAllCookies();
                  await ref.read(qqAuthProvider.notifier).logout();
                  _webController?.reload();
                  if (!mounted) return;
                  AppToast.show(context, '已清理，可切换账号重新登录',
                      success: true);
                },
                icon: const Icon(Icons.cleaning_services_rounded, size: 15),
                label: const Text('清理登录状态（切换账号）',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
          // ---------- WebView ----------
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InAppWebView(
                  onWebViewCreated: (controller) => _webController = controller,
                  initialUrlRequest: URLRequest(
                    url: WebUri('https://y.qq.com/'),
                  ),
                  // 强制桌面版网页：手机版 H5 没有扫码登录入口
                  initialSettings: InAppWebViewSettings(
                    userAgent:
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                    // 扫码登录框是 window.open 弹出的，必须在 WebView 内处理
                    supportMultipleWindows: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                  ),
                  onCreateWindow: (controller, createWindowRequest) async {
                    // 登录弹窗在当前 WebView 内打开
                    await controller.loadUrl(
                      urlRequest: createWindowRequest.request,
                    );
                    return true;
                  },
                ),
              ),
            ),
          ),
          // ---------- Cookie 兜底 ----------
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppColors.card(radius: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cookie_rounded,
                          color: AppColors.brand, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '抓取失败？手动粘贴 Cookie',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '登录 y.qq.com 后从浏览器开发者工具复制',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cookieController,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: '粘贴完整 Cookie 字符串',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
