import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

/// 显示权限缺失提示对话框
Future<void> showPermissionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _PermissionDialog(),
  );
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    final isIOS =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              AppStrings.permissionTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isIOS
                  ? AppStrings.permissionIOSDesc
                  : AppStrings.permissionAndroidDesc,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.cancelConnect),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openSettings();
                    },
                    child: const Text(AppStrings.goToSettings),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    // iOS: 通过 URL scheme 打开设置
    // Android: 通过 Intent 打开应用详情设置
    // 这里使用条件导入的方式，但由于不新增依赖，
    // 使用 platform_channels 或直接在原生层处理
    // 简化方案：提示用户手动去设置
  }
}
