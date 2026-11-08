import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

/// 更新完整流程：发现新版本确认 → 下载（进度弹窗，可取消）→ 安装/打开
Future<void> runAppUpdateFlow(
  BuildContext context,
  WidgetRef ref,
  AppUpdate update,
) async {
  final go = await showAppUpdateDialog(
    context,
    version: update.version,
    notes: update.notes,
  );
  if (go != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black38,
    builder: (_) => _UpdateDownloadDialog(update: update),
  );
}

/// 下载进度弹窗：内部驱动下载，完成后自动收起并拉起安装
class _UpdateDownloadDialog extends ConsumerStatefulWidget {
  final AppUpdate update;

  const _UpdateDownloadDialog({required this.update});

  @override
  ConsumerState<_UpdateDownloadDialog> createState() =>
      _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends ConsumerState<_UpdateDownloadDialog> {
  final _cancel = DownloadCancel();
  double _progress = 0; // 0.0 ~ 1.0
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final service = ref.read(updateServiceProvider);
    try {
      final path = await service.download(widget.update, (p) {
        if (mounted) setState(() => _progress = p);
      }, _cancel);
      if (!mounted) return;
      // 下载完成：拉起系统安装器 / 打开下载目录
      await service.installOrReveal(path);
      if (!mounted) return;
      if (Platform.isWindows) {
        AppToast.show(context, '已下载到下载目录，解压后运行新版本', success: true);
      }
      _close();
    } on DownloadCancelled {
      if (mounted) _close();
    } catch (e) {
      debugPrint('[update] download failed: $e');
      if (!mounted) return;
      AppToast.show(context, '下载失败：$e', error: true);
      _close();
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.downloading_rounded,
                    size: 20,
                    color: AppColors.brandDeep,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在下载 v${u.version}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (u.assetSize > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${(u.assetSize / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppColors.brandSoft,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandDeep,
              ),
            ),
            const SizedBox(height: 16),
            AppDialogButton(
              label: '取消下载',
              soft: true,
              onTap: () => _cancel.abort(), // 强制断开连接，卡住时也能立即取消
            ),
          ],
        ),
      ),
    );
  }
}
