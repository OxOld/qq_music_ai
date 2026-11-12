import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'mine_page.dart';

/// 根页面：「首页 / 我的」双 Tab + 迷你播放条
///
/// 竖屏：页面内品牌头部 + 底部 NavigationBar；
/// 横屏（车机投屏 / 平板）：顶部通栏品牌头部（拉满整宽）+ 左侧 NavigationRail，
/// 底部只保留迷你播放条，把纵向空间让给内容。
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

  void _select(int i) {
    setState(() => _index = i);
    // 切到「我的」时刷新歌单列表（首页添加/创建后能立刻看到）
    if (i == 1) _mineKey.currentState?.refresh();
  }

  /// Tab 内容（横竖屏切换时 State 保留，仅布局重建）
  Widget _pages() => IndexedStack(
    index: _index,
    children: [
      // 非 const：主题切换时重建 widget（State 保留，AppColors 取到新值）
      HomePage(),
      MinePage(key: _mineKey),
    ],
  );

  /// 竖屏底部导航栏
  Widget _bottomBar() => NavigationBar(
    selectedIndex: _index,
    onDestinationSelected: _select,
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
  );

  /// 横屏顶部通栏头部：按当前 Tab 显示对应品牌头部（拉满整宽，观感更整）
  Widget _topHeader() => _index == 0 ? const HomeHeader() : const MineHeader();

  @override
  Widget build(BuildContext context) {
    // 横屏（车机投屏 / 平板）：顶部通栏头部 + 左侧导航栏 + 右侧内容。
    // 用 MediaQuery.orientation（窗口 surface 方向）而非宽高比较：
    // 车机投屏窗口可能被系统旋转 90° 呈现，宽高比与 surface 方向不一致。
    final wide = MediaQuery.of(context).orientation == Orientation.landscape;
    // 状态栏白色图标（顶部为品牌渐变）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayLight,
      child: Scaffold(
        body: wide
            ? Column(
                children: [
                  _topHeader(),
                  Expanded(
                    child: Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: _select,
                          backgroundColor: Colors.white,
                          indicatorColor: AppColors.brandSoft,
                          minWidth: 78,
                          labelType: NavigationRailLabelType.all,
                          selectedIconTheme: IconThemeData(
                            color: AppColors.brandDeep,
                            size: 26,
                          ),
                          unselectedIconTheme: IconThemeData(
                            color: AppColors.textSecondary,
                            size: 26,
                          ),
                          selectedLabelTextStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandDeep,
                          ),
                          unselectedLabelTextStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.home_outlined),
                              selectedIcon: Icon(Icons.home_rounded),
                              label: Text('首页'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.person_outline_rounded),
                              selectedIcon: Icon(Icons.person_rounded),
                              label: Text('我的'),
                            ),
                          ],
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: AppColors.textPrimary.withValues(alpha: 0.08),
                        ),
                        Expanded(child: _pages()),
                      ],
                    ),
                  ),
                ],
              )
            : _pages(),
        bottomNavigationBar: wide
            ? MiniPlayer()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [MiniPlayer(), _bottomBar()],
              ),
      ),
    );
  }
}
