import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qq_music_ai/main.dart';

void main() {
  testWidgets('App 启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: QqMusicAiApp()));
    await tester.pump();

    expect(find.text('QQ 音乐 AI 歌单'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
