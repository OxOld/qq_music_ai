import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'mine_page.dart';

/// 根页面：底部「首页 / 我的」双 Tab + 迷你播放条
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;
  final _mineKey = GlobalKey<MinePageState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(),
          MinePage(key: _mineKey),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() => _index = i);
              // 切到「我的」时刷新歌单列表（首页添加/创建后能立刻看到）
              if (i == 1) _mineKey.currentState?.refresh();
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
