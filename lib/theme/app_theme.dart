import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题预设：主色 / 深色 / 浅底三件套
class ThemePreset {
  final String id;
  final String name;
  final Color brand;
  final Color brandDeep;
  final Color brandSoft;
  const ThemePreset(
    this.id,
    this.name,
    this.brand,
    this.brandDeep,
    this.brandSoft,
  );
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(
    'qq',
    'QQ 绿',
    Color(0xFF31C27C),
    Color(0xFF12996A),
    Color(0xFFE4F6ED),
  ),
  ThemePreset(
    'ocean',
    '海盐蓝',
    Color(0xFF2E7CF6),
    Color(0xFF1B5CD6),
    Color(0xFFE3EEFD),
  ),
  ThemePreset(
    'sunset',
    '落日橙',
    Color(0xFFF2762E),
    Color(0xFFD4571A),
    Color(0xFFFDEAE0),
  ),
  ThemePreset(
    'sakura',
    '樱花粉',
    Color(0xFFE85D9E),
    Color(0xFFC73A7D),
    Color(0xFFFBE7F1),
  ),
  ThemePreset(
    'grape',
    '葡萄紫',
    Color(0xFF8A5CF6),
    Color(0xFF683CDE),
    Color(0xFFEDE8FD),
  ),
];

/// 应用视觉规范：可切换主题色 + 柔和卡片风
///
/// brand / brandDeep / brandSoft / brandGradient 跟随当前预设，
/// 切换后自增 [themeVersion]，由根组件监听并重建整棵树。
abstract final class AppColors {
  static ThemePreset _preset = kThemePresets.first;

  static ThemePreset get preset => _preset;

  /// 切换主题时自增，监听方重建
  static final ValueNotifier<int> themeVersion = ValueNotifier<int>(0);

  /// 品牌主色
  static Color get brand => _preset.brand;

  /// 深色（渐变末端 / 选中态）
  static Color get brandDeep => _preset.brandDeep;

  /// 浅色底（徽标 / 选中态）
  static Color get brandSoft => _preset.brandSoft;

  /// 页面底色
  static const bg = Color(0xFFF3F6F4);

  static const success = Color(0xFF00A870);
  static const danger = Color(0xFFE34D59);
  static const dangerSoft = Color(0xFFFBEBED);

  static const textPrimary = Color(0xFF1C2420);
  static const textSecondary = Color(0xFF79847E);

  /// 主色渐变（按钮 / 头部）
  static LinearGradient get brandGradient => LinearGradient(
    colors: [brand, brandDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 切换主题（持久化）
  static Future<void> applyPreset(ThemePreset p) async {
    if (p.id == _preset.id) return;
    _preset = p;
    themeVersion.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_preset_id', p.id);
    } catch (_) {}
  }

  /// 启动时恢复上次选择
  static Future<void> loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('theme_preset_id');
      if (id == null) return;
      for (final p in kThemePresets) {
        if (p.id == id) {
          _preset = p;
          return;
        }
      }
    } catch (_) {}
  }

  /// 卡片装饰：白底、16 圆角、极浅阴影
  static BoxDecoration card({double radius = 16}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: const Color(0x141C2420),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// 全局主题
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    iconTheme: IconThemeData(color: AppColors.brand),
    dividerTheme: const DividerThemeData(
      color: Color(0x0F1C2420),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.brand,
      linearTrackColor: AppColors.brandSoft,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F7F6),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.brand, width: 1.4),
      ),
      hintStyle: const TextStyle(color: Color(0xFFA6B0AA), fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.brandSoft,
      surfaceTintColor: Colors.white,
      height: 66,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.brandDeep
              : AppColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? AppColors.brandDeep
              : AppColors.textSecondary,
        ),
      ),
    ),
  );
}
