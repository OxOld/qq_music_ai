import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'pages/root_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 后台播放：系统通知栏 / 锁屏媒体控制
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.qqmusicai.qq_music_ai.playback',
    androidNotificationChannelName: '音乐播放',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    androidNotificationIcon: 'drawable/ic_notification',
    notificationColor: const Color(0xFF31C27C),
  );
  runApp(const ProviderScope(child: QqMusicAiApp()));
}

class QqMusicAiApp extends StatelessWidget {
  const QqMusicAiApp({super.key});

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
