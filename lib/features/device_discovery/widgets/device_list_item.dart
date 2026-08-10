import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/device_icon_utils.dart';
import '../providers/device_provider.dart';
import 'loading_wave_overlay.dart';

class DeviceListItem extends ConsumerWidget {
  final Device device;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 桌面端右键点击（用于唤起移除弹窗）
  final VoidCallback? onSecondaryTap;

  const DeviceListItem({
    super.key,
    required this.device,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    final connState =
        ref.watch(connectionStatesProvider)[device.id] ??
        DeviceConnectionState.unconnected;
    final isConnecting = connState == DeviceConnectionState.connecting;
    // 已连接高亮仅在该设备在线时显示；离线后自动取消高亮
    final isConnected =
        connState == DeviceConnectionState.connected && device.isOnline;

    return LoadingWaveOverlay(
      active: isConnecting,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: isConnected ? AppColors.primary.withValues(alpha: 0.08) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isConnected
              ? BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // 设备头像
                Container(
                  width: 44,
                  height: 44,
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
                    deviceTypeIcon(device.typeIcon),
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // 设备信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _buildStatusRow(context, colors, theme, connState),
                    ],
                  ),
                ),
                // 右侧图标
                _buildTrailing(connState, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    AppColorScheme colors,
    ThemeData theme,
    DeviceConnectionState connState,
  ) {
    if (connState == DeviceConnectionState.connecting) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            AppStrings.connecting,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      );
    }

    // 仅当在线且已连接时显示"已连接"
    if (connState == DeviceConnectionState.connected && device.isOnline) {
      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.online,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            AppStrings.connectedStatus,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.online),
          ),
        ],
      );
    }

    // 其他情况显示在线/离线状态
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: device.isOnline ? AppColors.online : AppColors.offline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          device.isOnline ? AppStrings.online : AppStrings.offline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: device.isOnline ? AppColors.online : colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTrailing(
    DeviceConnectionState connState,
    AppColorScheme colors,
  ) {
    // 仅当在线且已连接时显示对勾
    if (connState == DeviceConnectionState.connected && device.isOnline) {
      return Icon(Icons.check_circle, color: AppColors.online, size: 22);
    }
    if (connState == DeviceConnectionState.connecting) {
      return const SizedBox.shrink();
    }
    return Icon(Icons.link, color: colors.iconSecondary, size: 20);
  }
}
