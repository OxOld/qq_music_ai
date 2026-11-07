import 'package:flutter/material.dart';

/// 应用视觉规范：QQ音乐绿 + 柔和卡片风
abstract final class AppColors {
  /// QQ 音乐品牌绿
  static const brand = Color(0xFF31C27C);

  /// 深绿（渐变末端）
  static const brandDeep = Color(0xFF12996A);

  /// 浅绿底（徽标 / 选中态）
  static const brandSoft = Color(0xFFE4F6ED);

  /// 页面底色
  static const bg = Color(0xFFF3F6F4);

  static const success = Color(0xFF00A870);
  static const danger = Color(0xFFE34D59);
  static const dangerSoft = Color(0xFFFBEBED);

  static const textPrimary = Color(0xFF1C2420);
  static const textSecondary = Color(0xFF79847E);

  /// 主色渐变（按钮 / 头部）
  static const brandGradient = LinearGradient(
    colors: [brand, brandDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
    iconTheme: const IconThemeData(color: AppColors.brand),
    dividerTheme: const DividerThemeData(
      color: Color(0x0F1C2420),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
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
        borderSide: const BorderSide(color: AppColors.brand, width: 1.4),
      ),
      hintStyle: const TextStyle(
        color: Color(0xFFA6B0AA),
        fontSize: 14,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.brandSoft,
      surfaceTintColor: Colors.white,
      height: 66,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.brandDeep
                : AppColors.textSecondary,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? AppColors.brandDeep
                : AppColors.textSecondary,
          )),
    ),
  );
}
