import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'mine_page.dart';

/// 根页面：底部「首页 / 我的」双 Tab + 迷你播放条
///
/// 监听主题切换：AppColors 是静态取值，需要整棵树重跑 build 才会换色
/// （tab 状态与各页 State 均保留，仅重建 widget）。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;
  final _mineKey = GlobalKey<MinePageState>();

  @override
  void initState() {
    super.initState();
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
    // 状态栏白色图标（顶部为品牌渐变）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayLight,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            // 非 const：主题切换时重建 widget（State 保留，AppColors 取到新值）
            HomePage(),
            MinePage(key: _mineKey),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiniPlayer(),
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
      ),
    );
  }
}
