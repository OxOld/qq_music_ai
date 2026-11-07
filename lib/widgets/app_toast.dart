import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 轻量 Toast（替代 TToast，保持深色圆角胶囊外观）
class AppToast {
  AppToast._();

  static void show(BuildContext context, String message,
      {bool error = false, bool success = false}) {
    final bg = error
        ? AppColors.danger
        : success
            ? AppColors.success
            : const Color(0xF0323A36);
    final icon = error
        ? Icons.error_outline_rounded
        : success
            ? Icons.check_circle_rounded
            : Icons.info_outline_rounded;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 6,
          behavior: SnackBarBehavior.floating,
          backgroundColor: bg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          duration: Duration(milliseconds: error ? 3200 : 2000),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
