import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 品牌渐变主按钮（设置页 / 提示词页共用）
///
/// [loading] 为 true 时显示转圈并禁用点击；[onTap] 为 null 也可禁用。
class GradientButton extends StatelessWidget {
  /// 按钮文案
  final String label;

  /// 左侧图标
  final IconData icon;

  /// 点击回调
  final VoidCallback? onTap;

  /// 是否处于加载中（显示 [loadingLabel] 与转圈）
  final bool loading;

  /// 加载中的文案（为空则沿用 [label]）
  final String? loadingLabel;

  /// 垂直内边距（设置页大按钮 13，卡片内按钮 12）
  final double verticalPadding;

  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.loading = false,
    this.loadingLabel,
    this.verticalPadding = 13,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = loading || onTap == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon, size: 19, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  loading ? (loadingLabel ?? label) : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
