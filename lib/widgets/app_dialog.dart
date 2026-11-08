import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 统一风格弹窗：图标 + 居中标题 + 胶囊按钮。
/// 替代默认 AlertDialog（左对齐标题 + 平面文字按钮），与整体卡片风格一致。

/// 确认弹窗；destructive 场景传 danger: true，确认键变红
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: danger ? AppColors.dangerSoft : AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: danger ? AppColors.danger : AppColors.brandDeep,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppDialogButton(
                    label: cancelLabel,
                    soft: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDialogButton(
                    label: confirmLabel,
                    danger: danger,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed == true;
}

/// 输入弹窗（改名等）：确认时返回去空格后的值；取消或空白返回 null
Future<String?> showAppInputDialog(
  BuildContext context, {
  required String title,
  String initialText = '',
  String hintText = '',
  int maxLength = 40,
  required String confirmLabel,
  IconData icon = Icons.edit_rounded,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => _AppInputDialog(
      title: title,
      initialText: initialText,
      hintText: hintText,
      maxLength: maxLength,
      confirmLabel: confirmLabel,
      icon: icon,
    ),
  );
}

/// 处理中弹窗（不可点外部关闭），结束后由调用方 Navigator.pop 关闭
void showAppProgressDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black38,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.6),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 发现新版本弹窗：更新说明可滚动；返回 true = 立即更新
Future<bool> showAppUpdateDialog(
  BuildContext context, {
  required String version,
  required String notes,
}) async {
  final go = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_alt_rounded,
                  size: 22,
                  color: AppColors.brandDeep,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '发现新版本 v$version',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      notes.trim().isEmpty
                          ? '体验优化与问题修复'
                          : notes.trim().replaceAll('**', ''),
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AppDialogButton(
                      label: '下次再说',
                      soft: true,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppDialogButton(
                      label: '立即更新',
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return go == true;
}

/// 胶囊弹窗按钮：soft=浅底取消键；danger=红底确认键；默认品牌渐变。
/// 一次性触发锁：弹窗退出动画期间按钮仍挂在树上，连点会误 pop 弹窗
/// 底下的页面（触发 framework 的 _dependents.isEmpty 断言），只允许触发一次。
class AppDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool soft;
  final bool danger;
  final bool enabled;

  const AppDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.soft = false,
    this.danger = false,
    this.enabled = true,
  });

  @override
  State<AppDialogButton> createState() => AppDialogButtonState();
}

class AppDialogButtonState extends State<AppDialogButton> {
  bool _fired = false;

  void _handle() {
    if (_fired) return;
    _fired = true;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final active = w.enabled && !_fired;
    if (w.soft) {
      return Material(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: active ? _handle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Text(
                w.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: w.danger ? null : AppColors.brandGradient,
        color: w.danger ? AppColors.danger : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: active
            ? [
                BoxShadow(
                  color: (w.danger ? AppColors.danger : AppColors.brand)
                      .withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: active ? _handle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Text(
                w.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 输入弹窗内部实现：监听输入内容，空白时禁用确认键
class _AppInputDialog extends StatefulWidget {
  final String title;
  final String initialText;
  final String hintText;
  final int maxLength;
  final String confirmLabel;
  final IconData icon;

  const _AppInputDialog({
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.maxLength,
    required this.confirmLabel,
    required this.icon,
  });

  @override
  State<_AppInputDialog> createState() => _AppInputDialogState();
}

class _AppInputDialogState extends State<_AppInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _submitted = false; // 防连点/键盘确认重复 pop

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    _submitted = true;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, size: 22, color: AppColors.brandDeep),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: widget.maxLength,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppDialogButton(
                    label: '取消',
                    soft: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDialogButton(
                    label: widget.confirmLabel,
                    onTap: _submit,
                    enabled: canSave,
                    soft: !canSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
