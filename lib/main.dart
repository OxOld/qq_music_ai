import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'pages/root_page.dart';
import 'providers/providers.dart';
import 'services/background_keepalive.dart';
import 'services/player_service.dart';
import 'services/qq_music_client.dart';
import 'theme/app_theme.dart';

/// 全局 provider 容器：播放器服务的换链接回调需要在无 context 的
/// main 里读登录态（qqAuthProvider 每次取最新 state）
final _container = ProviderContainer();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先恢复主题，媒体通知色跟随
  await AppColors.loadPersisted();
  // 后台播放：系统通知栏 / 锁屏媒体控制
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.qqmusicai.qq_music_ai.playback',
    androidNotificationChannelName: '音乐播放',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    androidNotificationIcon: 'drawable/ic_notification',
    notificationColor: AppColors.brand,
  );
  // 系统级后台保活（Android）：App 进程被杀后由系统每 12h 续期登录态，
  // 实现「不开 App 也一劳永逸」；注册失败不影响启动
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(registerKeepAliveTask());
  }
  // 恢复队列播放前批量换新链接：持久化的 vkey 链接数小时即失效，
  // 旧链接直接播会失败（表现为「迷你条点播放没反应」）。
  // 3 路并行预取，client 侧 60 分钟缓存让近期播过的秒回。
  PlayerService.instance.urlRefresher = (mids) async {
    final client = _container.read(qqMusicClientProvider);
    final auth = _container.read(qqAuthProvider);
    final out = List<String?>.filled(mids.length, null);
    var ok = 0;
    var authFailed = 0;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < mids.length) {
        final i = cursor++;
        try {
          final url = await client.getPlayUrl(auth, mids[i]);
          if (url.isNotEmpty) {
            out[i] = url;
            ok++;
          }
        } on QQMusicAuthExpiredException {
          authFailed++;
        } catch (_) {}
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    // 只有「全部失败且全是登录态异常」才算登录过期：单曲无版权/需会员
    // 也会抛同一异常，若按「任意一首异常」判定，队列里有一首播不了就会
    // 误报登录过期——表现为能正常播放却反复弹「重新登录」。
    final authExpired = ok == 0 && authFailed > 0;
    debugPrint(
      '[diag] refresh urls total=${mids.length} ok=$ok '
      'authFailed=$authFailed authExpired=$authExpired',
    );
    return UrlRefreshResult(out, authExpired: authExpired);
  };
  runApp(
    UncontrolledProviderScope(container: _container, child: const QqMusicAiApp()),
  );
}

class QqMusicAiApp extends StatefulWidget {
  const QqMusicAiApp({super.key});

  @override
  State<QqMusicAiApp> createState() => _QqMusicAiAppState();
}

class _QqMusicAiAppState extends State<QqMusicAiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 主题色切换：重建整棵树（页面状态保留）
    AppColors.themeVersion.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppColors.themeVersion.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台补一次登录态续期（进程被冻结期间 12h 定时器不会走）
    if (state == AppLifecycleState.resumed) {
      _container.read(qqAuthProvider.notifier).refreshOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QQ 音乐 AI 歌单',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootPage(),
    );
  }
}
