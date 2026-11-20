import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'pages/root_page.dart';
import 'providers/providers.dart';
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
  // 恢复队列播放前批量换新链接：持久化的 vkey 链接数小时即失效，
  // 旧链接直接播会失败（表现为「迷你条点播放没反应」）。
  // 3 路并行预取，client 侧 60 分钟缓存让近期播过的秒回。
  PlayerService.instance.urlRefresher = (mids) async {
    final client = _container.read(qqMusicClientProvider);
    final auth = _container.read(qqAuthProvider);
    final out = List<String?>.filled(mids.length, null);
    var authExpired = false;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < mids.length) {
        final i = cursor++;
        try {
          out[i] = await client.getPlayUrl(auth, mids[i]);
        } on QQMusicAuthExpiredException {
          authExpired = true;
        } catch (_) {}
      }
    }

    await Future.wait([worker(), worker(), worker()]);
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

class _QqMusicAiAppState extends State<QqMusicAiApp> {
  @override
  void initState() {
    super.initState();
    // 主题色切换：重建整棵树（页面状态保留）
    AppColors.themeVersion.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.themeVersion.removeListener(_onThemeChanged);
    super.dispose();
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
