import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'mine_page.dart';

/// 根页面：「首页 / 我的」双 Tab + 迷你播放条
///
/// 竖屏：底部 NavigationBar；横屏（车机投屏 / 平板）：左侧自绘侧栏
/// （导航按钮垂直居中，避免矮窗口/旋转窗口下贴边被裁），
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

  /// 横屏侧栏：两个导航按钮**垂直居中**。
  /// 不用 NavigationRail：其目的地固定顶部对齐，车机投屏的矮窗口/旋转窗口下
  /// 贴边按钮容易被裁掉；自绘同外观侧栏并居中放置（侧栏本身已延伸到状态栏下，
  /// 占满整列高度，居中后上下留白对称）。
  Widget _sideRail() {
    return Container(
      width: 78,
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _railItem(0, Icons.home_outlined, Icons.home_rounded, '首页'),
          const SizedBox(height: 20),
          _railItem(
            1,
            Icons.person_outline_rounded,
            Icons.person_rounded,
            '我的',
          ),
        ],
      ),
    );
  }

  Widget _railItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    final selected = _index == index;
    final color = selected ? AppColors.brandDeep : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _select(index),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, size: 26, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 横屏（车机投屏 / 平板）：左侧导航栏 + 右侧内容。
    // 用 MediaQuery.orientation（窗口 surface 方向）而非宽高比较：
    // 车机投屏窗口可能被系统旋转 90° 呈现，宽高比与 surface 方向不一致。
    final wide = MediaQuery.of(context).orientation == Orientation.landscape;
    // 状态栏白色图标（顶部为品牌渐变）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayLight,
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  _sideRail(),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.textPrimary.withValues(alpha: 0.08),
                  ),
                  Expanded(child: _pages()),
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
