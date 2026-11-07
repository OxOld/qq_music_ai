import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'pages/root_page.dart';
import 'theme/app_theme.dart';

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
  runApp(const ProviderScope(child: QqMusicAiApp()));
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
