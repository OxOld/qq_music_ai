import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qq_music_ai/main.dart';
import 'package:qq_music_ai/services/player_service.dart';

void main() {
  testWidgets('App 启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: QqMusicAiApp()));
    await tester.pump();

    // 首页标题与输入框提示可见（设置入口在「我的」页，不在首屏）
    expect(find.text('QQ 音乐 AI 歌单'), findsOneWidget);
    expect(find.textContaining('描述你想要的歌单'), findsOneWidget);

    // 播放器是全局单例，测试结束主动释放，避免周期性定时器悬空
    await PlayerService.instance.dispose();
  });
}
