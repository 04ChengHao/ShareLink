import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device_discovery/providers/device_provider.dart';
import '../models/file_item.dart';

/// 用户手动选中的设备
///
/// - `null`：未手动选择（由 [effectiveSelectedDeviceProvider] 自动决定）
/// - `'本机'`：手动选中本机
/// - 设备名称：手动选中某设备
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, String?>(
      SelectedDeviceNotifier.new,
    );

class SelectedDeviceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  set device(String? value) => state = value;
}

/// 当前已连接的设备列表（过滤出 WebSocket 已建立的设备）
final connectedDevicesProvider = Provider<List<Device>>((ref) {
  final allDevices = ref.watch(previouslyConnectedDevicesProvider);
  final connStates = ref.watch(connectionStatesProvider);
  return allDevices
      .where((d) => connStates[d.id] == DeviceConnectionState.connected)
      .toList();
});

/// 实际生效的选中设备
///
/// 优先级：
/// 1. 用户手动选中的设备仍有效（本机 或 仍连接中的设备）→ 使用用户选择
/// 2. 有已连接设备 → 自动选中第一个
/// 3. 无已连接设备 → 本机（null）
final effectiveSelectedDeviceProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedDeviceProvider);
  final connectedDevices = ref.watch(connectedDevicesProvider);

  // 用户手动选中的情况
  if (selected != null) {
    if (selected == '本机') return null; // 显式选中本机
    // 检查选中的设备是否仍连接中
    final stillConnected = connectedDevices.any((d) => d.name == selected);
    if (stillConnected) return selected;
    // 选中的设备已断开 → 回落到自动选择
  }

  // 自动选择：有连接设备时选中第一个，否则本机
  if (connectedDevices.isNotEmpty) {
    return connectedDevices.first.name;
  }
  return null; // 本机
});

/// 当前路径
final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '/';

  set path(String value) => state = value;
}

/// 文件分类筛选
final fileCategoryProvider = NotifierProvider<FileCategoryNotifier, String>(
  FileCategoryNotifier.new,
);

class FileCategoryNotifier extends Notifier<String> {
  @override
  String build() => '图片';

  set category(String value) => state = value;
}

/// 文件列表
final fileListProvider = NotifierProvider<FileListNotifier, List<FileItem>>(
  FileListNotifier.new,
);

class FileListNotifier extends Notifier<List<FileItem>> {
  @override
  List<FileItem> build() {
    // TODO: 从 SMB 连接获取真实文件列表
    return const [
      FileItem(name: '风景.jpg', path: '/风景.jpg'),
      FileItem(name: '截图.png', path: '/截图.png'),
      FileItem(name: '头像.jpg', path: '/头像.jpg'),
      FileItem(name: '设计稿.png', path: '/设计稿.png'),
      FileItem(name: '壁纸.jpg', path: '/壁纸.jpg'),
      FileItem(name: '相册1.jpg', path: '/相册1.jpg'),
    ];
  }

  set files(List<FileItem> value) => state = value;
}
