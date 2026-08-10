import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/neuomorphic_style.dart';
import '../providers/device_provider.dart';
import '../services/device_service.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/device_list_item.dart';
import '../widgets/permission_dialog.dart';

class DeviceDiscoveryView extends ConsumerWidget {
  const DeviceDiscoveryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (PlatformUtils.isDesktop) {
      return const _DesktopHome();
    }
    return const _MobileHome();
  }
}

// ---------------------------------------------------------------------------
// 连接流程（手机端和桌面端共用）
// ---------------------------------------------------------------------------

/// 开启/关闭连接
Future<void> _toggle(
  BuildContext context,
  WidgetRef ref,
  bool isEnabled,
) async {
  final next = !isEnabled;
  ref.read(connectionEnabledProvider.notifier).enabled = next;

  if (next) {
    try {
      await ref.read(deviceServiceProvider).start();
      // 连接开启后，立即对所有在线的已连接过设备触发自动重连，
      // 避免因 _onPresence 幂等跳过而错过重连时机。
      ref
          .read(previouslyConnectedDevicesProvider.notifier)
          .reconnectAllOnlineWhenEnabled();
    } on PermissionException {
      ref.read(connectionEnabledProvider.notifier).enabled = false;
      if (!context.mounted) return;
      await showPermissionDialog(context);
    } catch (_) {
      ref.read(connectionEnabledProvider.notifier).enabled = false;
    }
  } else {
    await ref.read(deviceServiceProvider).stop();
  }
}

/// 连接到设备
Future<void> _connectToDevice(
  BuildContext context,
  WidgetRef ref,
  Device device, {
  required bool isReconnect,
}) async {
  final service = ref.read(deviceServiceProvider);

  // 检查当前是否已连接 → 弹出断开连接弹窗
  final connState = ref.read(connectionStatesProvider)[device.id];
  if (connState == DeviceConnectionState.connected && device.isOnline) {
    await _showDisconnectDialog(context, ref, device);
    return;
  }

  // 重连：用缓存密码直接尝试
  if (isReconnect) {
    final savedPwd = ref
        .read(previouslyConnectedDevicesProvider.notifier)
        .getPassword(device.id);
    ref
        .read(connectionStatesProvider.notifier)
        .set(device.id, DeviceConnectionState.connecting);

    final result = await service.connectToDevice(device, password: savedPwd);
    if (!context.mounted) return;

    if (result == ConnectResult.success) {
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.connected);
    } else if (result == ConnectResult.authFailed) {
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.unconnected);
      await _connectWithDialog(context, ref, device);
    } else {
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.unconnected);
      _showToast(context, AppStrings.connectFailed);
    }
    return;
  }

  // 首次连接：弹对话框
  await _connectWithDialog(context, ref, device);
}

/// 断开连接弹窗
Future<void> _showDisconnectDialog(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: AppStrings.disconnectTitle,
    content: AppStrings.disconnectContent,
    confirmText: AppStrings.disconnectBtn,
    icon: Icons.link_off_rounded,
    iconColor: Colors.red,
  );
  if (confirmed == true) {
    await ref.read(deviceServiceProvider).disconnectDevice(device.id);
    ref
        .read(connectionStatesProvider.notifier)
        .set(device.id, DeviceConnectionState.unconnected);
    if (!context.mounted) return;
    _showToast(context, AppStrings.disconnectedToast);
  }
}

/// 弹对话框连接
Future<void> _connectWithDialog(
  BuildContext context,
  WidgetRef ref,
  Device device, [
  String? errorMessage,
  String? initialPassword,
]) async {
  final service = ref.read(deviceServiceProvider);
  final result = await showConnectionDialog(
    context: context,
    device: device,
    errorMessage: errorMessage,
    initialPassword: initialPassword,
  );
  if (result == null || !result.confirmed) return;
  if (!context.mounted) return;

  ref
      .read(connectionStatesProvider.notifier)
      .set(device.id, DeviceConnectionState.connecting);

  final connectResult = await service.connectToDevice(
    device,
    password: result.password,
  );
  if (!context.mounted) return;

  switch (connectResult) {
    case ConnectResult.success:
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.connected);
      ref
          .read(previouslyConnectedDevicesProvider.notifier)
          .onConnected(device, password: result.password);
      _showToast(context, AppStrings.connectedToast);
      break;
    case ConnectResult.authFailed:
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.unconnected);
      await _connectWithDialog(
        context,
        ref,
        device,
        AppStrings.passwordError,
        result.password,
      );
      break;
    case ConnectResult.rejected:
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.unconnected);
      await _connectWithDialog(context, ref, device, AppStrings.peerRejected);
      break;
    case ConnectResult.networkError:
    case ConnectResult.timeout:
      ref
          .read(connectionStatesProvider.notifier)
          .set(device.id, DeviceConnectionState.unconnected);
      await _connectWithDialog(context, ref, device, AppStrings.connectFailed);
      break;
  }
}

void _showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 确认移除已连接过设备（使用与连接弹窗一致的统一样式）
Future<void> _confirmRemoveDevice(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: AppStrings.removeDeviceTitle,
    content: AppStrings.removeDeviceContent,
    confirmText: AppStrings.confirm,
    icon: Icons.delete_outline_rounded,
    iconColor: Colors.red,
  );
  if (confirmed == true) {
    ref.read(previouslyConnectedDevicesProvider.notifier).remove(device.id);
  }
}

// ---------------------------------------------------------------------------
// 手机端首页
// ---------------------------------------------------------------------------

class _MobileHome extends ConsumerStatefulWidget {
  const _MobileHome();

  @override
  ConsumerState<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends ConsumerState<_MobileHome> {
  @override
  void initState() {
    super.initState();
    // 如果连接已开启，进入页面时自动启动服务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(connectionEnabledProvider)) {
        ref.read(deviceServiceProvider).start().then((_) {
          // 启动完成后立刻尝试重连在线设备
          ref
              .read(previouslyConnectedDevicesProvider.notifier)
              .reconnectAllOnlineWhenEnabled();
        }).catchError((_) {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final previouslyConnected = ref.watch(previouslyConnectedDevicesProvider);
    final nearbyAsync = ref.watch(nearbyDevicesProvider);
    final isSearchingAsync = ref.watch(isSearchingDevicesProvider);
    final isEnabled = ref.watch(connectionEnabledProvider);

    final nearby = nearbyAsync.value ?? const <Device>[];
    final isSearching = isSearchingAsync.value ?? false;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: const Text(
          AppStrings.appName,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final centerY = constraints.maxHeight / 2;
          final topY = constraints.maxHeight * 0.15;
          const buttonSize = 120.0;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: isEnabled
                    ? topY - buttonSize / 2
                    : centerY - buttonSize / 2,
                height: buttonSize,
                child: Center(
                  child: _PowerButton(
                    onTap: () => _toggle(context, ref, isEnabled),
                    isEnabled: isEnabled,
                    size: buttonSize,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: isEnabled
                    ? topY + buttonSize / 2 + 16
                    : centerY + buttonSize / 2 + 24,
                child: Center(
                  child: Text(
                    isEnabled
                        ? AppStrings.connectedHint
                        : AppStrings.connectHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColorScheme.of(context).textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: isEnabled ? 0 : -constraints.maxHeight,
                height: constraints.maxHeight - topY - buttonSize / 2 - 40,
                child: _MobileDeviceList(
                  previouslyConnected: previouslyConnected,
                  nearbyDevices: nearby,
                  isSearching: isSearching,
                  onRefresh: () => ref.read(deviceServiceProvider).refresh(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MobileDeviceList extends ConsumerWidget {
  final List<Device> previouslyConnected;
  final List<Device> nearbyDevices;
  final bool isSearching;
  final VoidCallback onRefresh;

  const _MobileDeviceList({
    required this.previouslyConnected,
    required this.nearbyDevices,
    required this.isSearching,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 过滤掉已连接过的设备，且仅保留在线的附近设备（离线设备自动移出列表）
    final connectedIds = previouslyConnected.map((d) => d.id).toSet();
    final nearby = nearbyDevices
        .where((d) => !connectedIds.contains(d.id) && d.isOnline)
        .toList();

    // 已连接过设备是否全部离线（无已连接过设备时视为 true）
    final allPrevOffline = previouslyConnected.every((d) => !d.isOnline);
    // 仅当附近无设备、且已连接过设备全部离线（或无已连接过设备）、且不在搜索中时显示空结果
    final showEmpty = nearby.isEmpty && allPrevOffline && !isSearching;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: AppColorScheme.of(context).glassBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColorScheme.of(context).glassBorder),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).padding.bottom,
          ),
          children: [
            // 标题：设备发现 + 刷新按钮（同一行，loading 时刷新按钮不消失）
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
              child: Row(
                children: [
                  Text(
                    AppStrings.deviceDiscovery,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColorScheme.of(context).textPrimary,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.refresh,
                        size: 18,
                        color: AppColorScheme.of(context).iconSecondary,
                      ),
                      onPressed: onRefresh,
                      tooltip: '重新搜索',
                    ),
                  ),
                ],
              ),
            ),
            // 搜索中进度条
            if (isSearching)
              const Padding(
                padding: EdgeInsets.only(left: 8, right: 8, bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            // 已连接过设备
            if (previouslyConnected.isNotEmpty) ...[
              _buildSectionTitle(context, AppStrings.connectedDevices),
              ...previouslyConnected.map(
                (device) => DeviceListItem(
                  device: device,
                  onTap: () =>
                      _connectToDevice(context, ref, device, isReconnect: true),
                  onLongPress: () => _confirmRemoveDevice(context, ref, device),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 附近设备
            if (nearby.isNotEmpty) ...[
              if (previouslyConnected.isNotEmpty) const Divider(height: 32),
              _buildSectionTitle(context, AppStrings.nearbyDevices),
              ...nearby.map(
                (device) => DeviceListItem(
                  device: device,
                  onTap: () => _connectToDevice(
                    context,
                    ref,
                    device,
                    isReconnect: false,
                  ),
                ),
              ),
            ] else if (showEmpty) ...[
              if (previouslyConnected.isNotEmpty) const Divider(height: 32),
              _buildEmptyHint(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColorScheme.of(context).textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: 48,
              color: AppColorScheme.of(
                context,
              ).textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.noNearbyDevices,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorScheme.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.noConnectionHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorScheme.of(
                  context,
                ).textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端首页
// ---------------------------------------------------------------------------

class _DesktopHome extends ConsumerStatefulWidget {
  const _DesktopHome();

  @override
  ConsumerState<_DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends ConsumerState<_DesktopHome> {
  @override
  void initState() {
    super.initState();
    // 如果连接已开启，进入页面时自动启动服务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(connectionEnabledProvider)) {
        ref.read(deviceServiceProvider).start().then((_) {
          // 启动完成后立刻尝试重连在线设备
          ref
              .read(previouslyConnectedDevicesProvider.notifier)
              .reconnectAllOnlineWhenEnabled();
        }).catchError((_) {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final previouslyConnected = ref.watch(previouslyConnectedDevicesProvider);
    final nearbyAsync = ref.watch(nearbyDevicesProvider);
    final isSearchingAsync = ref.watch(isSearchingDevicesProvider);
    final isEnabled = ref.watch(connectionEnabledProvider);

    final nearby = nearbyAsync.value ?? const <Device>[];
    final isSearching = isSearchingAsync.value ?? false;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final halfWidth = width / 2;
          const buttonSize = 140.0;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: isEnabled
                    ? (halfWidth - buttonSize) / 2
                    : (width - buttonSize) / 2,
                top: (height - buttonSize) / 2 - 30,
                width: buttonSize,
                height: buttonSize,
                child: _PowerButton(
                  onTap: () => _toggle(context, ref, isEnabled),
                  isEnabled: isEnabled,
                  size: buttonSize,
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                left: isEnabled
                    ? (halfWidth - buttonSize) / 2
                    : (width - buttonSize) / 2,
                top: isEnabled
                    ? (height + buttonSize) / 2 - 16
                    : (height + buttonSize) / 2 + 16,
                width: buttonSize,
                child: Text(
                  isEnabled ? AppStrings.connectedHint : AppStrings.connectHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.of(context).textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                top: 0,
                right: isEnabled ? 0 : -halfWidth,
                bottom: 0,
                width: halfWidth,
                child: _DesktopDevicePanel(
                  previouslyConnected: previouslyConnected,
                  nearbyDevices: nearby,
                  isSearching: isSearching,
                  onRefresh: () => ref.read(deviceServiceProvider).refresh(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 桌面端右侧设备面板
class _DesktopDevicePanel extends ConsumerWidget {
  final List<Device> previouslyConnected;
  final List<Device> nearbyDevices;
  final bool isSearching;
  final VoidCallback onRefresh;

  const _DesktopDevicePanel({
    required this.previouslyConnected,
    required this.nearbyDevices,
    required this.isSearching,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 过滤掉已连接过的设备，且仅保留在线的附近设备（离线设备自动移出列表）
    final connectedIds = previouslyConnected.map((d) => d.id).toSet();
    final nearby = nearbyDevices
        .where((d) => !connectedIds.contains(d.id) && d.isOnline)
        .toList();

    // 已连接过设备是否全部离线（无已连接过设备时视为 true）
    final allPrevOffline = previouslyConnected.every((d) => !d.isOnline);
    // 仅当附近无设备、且已连接过设备全部离线（或无已连接过设备）、且不在搜索中时显示空结果
    final showEmpty = nearby.isEmpty && allPrevOffline && !isSearching;

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: NeuomorphicStyle.adaptive(theme.brightness, blur: 20),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.deviceDiscovery,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.refresh,
                        size: 18,
                        color: AppColorScheme.of(context).iconSecondary,
                      ),
                      onPressed: onRefresh,
                      tooltip: '重新搜索',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isSearching) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
                Text(
                  AppStrings.searchingNearbyDevices,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColorScheme.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: ListView(
                  children: [
                    if (previouslyConnected.isNotEmpty) ...[
                      _buildSectionTitle(context, AppStrings.connectedDevices),
                      ...previouslyConnected.map(
                        (device) => DeviceListItem(
                          device: device,
                          onTap: () => _connectToDevice(
                            context,
                            ref,
                            device,
                            isReconnect: true,
                          ),
                          onLongPress: () =>
                              _confirmRemoveDevice(context, ref, device),
                          // 桌面端：右键也能唤起移除弹窗
                          onSecondaryTap: () =>
                              _confirmRemoveDevice(context, ref, device),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (nearby.isNotEmpty) ...[
                      if (previouslyConnected.isNotEmpty)
                        const Divider(height: 32),
                      _buildSectionTitle(context, AppStrings.nearbyDevices),
                      ...nearby.map(
                        (device) => DeviceListItem(
                          device: device,
                          onTap: () => _connectToDevice(
                            context,
                            ref,
                            device,
                            isReconnect: false,
                          ),
                        ),
                      ),
                    ] else if (showEmpty) ...[
                      if (previouslyConnected.isNotEmpty)
                        const Divider(height: 32),
                      _buildEmptyHint(context),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColorScheme.of(context).textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: 48,
              color: AppColorScheme.of(
                context,
              ).textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.noNearbyDevices,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorScheme.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.noConnectionHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorScheme.of(
                  context,
                ).textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 电源开关按钮
// ---------------------------------------------------------------------------

class _PowerButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isEnabled;
  final double size;

  const _PowerButton({
    required this.onTap,
    required this.isEnabled,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isEnabled
                ? [AppColors.primary, AppColors.primaryLight]
                : [const Color(0x66FFFFFF), const Color(0x1AFFFFFF)],
          ),
          border: Border.all(color: const Color(0x66FFFFFF), width: 2),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.power_settings_new,
            key: ValueKey(isEnabled),
            size: size * 0.4,
            color: isEnabled
                ? Colors.white
                : AppColorScheme.of(context).textSecondary,
          ),
        ),
      ),
    );
  }
}
