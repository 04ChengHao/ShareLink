import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/device_icon_utils.dart';
import '../models/device.dart';
import '../../settings/widgets/password_input_field.dart';

/// 连接对话框返回结果
class ConnectionDialogResult {
  final bool confirmed;
  final String? password;

  const ConnectionDialogResult({required this.confirmed, this.password});
}

/// 显示连接确认对话框
Future<ConnectionDialogResult?> showConnectionDialog({
  required BuildContext context,
  required Device device,
  String? errorMessage,
  String? initialPassword,
}) {
  return showDialog<ConnectionDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ConnectionDialog(
      device: device,
      errorMessage: errorMessage,
      initialPassword: initialPassword,
    ),
  );
}

class _ConnectionDialog extends StatefulWidget {
  final Device device;
  final String? errorMessage;
  final String? initialPassword;

  const _ConnectionDialog({
    required this.device,
    this.errorMessage,
    this.initialPassword,
  });

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late String _password;

  @override
  void initState() {
    super.initState();
    _password = widget.initialPassword ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // 限制宽度，避免桌面端按钮拉伸过宽
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Text(
                AppStrings.connectDeviceTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              // 设备信息
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.primaryLight.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                    child: Icon(
                      deviceTypeIcon(widget.device.typeIcon),
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.device.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.device.ip,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 密码输入
              if (widget.device.hasPassword) ...[
                const SizedBox(height: 16),
                PasswordInputField(
                  value: _password,
                  onChanged: (v) => _password = v,
                ),
              ],
              // 错误信息
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              // 按钮行
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const ConnectionDialogResult(confirmed: false)),
                      child: Text(AppStrings.cancelConnect),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        ConnectionDialogResult(
                          confirmed: true,
                          password: widget.device.hasPassword
                              ? _password
                              : null,
                        ),
                      ),
                      child: Text(AppStrings.confirmConnect),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
