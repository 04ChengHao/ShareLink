import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/global_providers.dart';
import '../../../core/services/device_info_service.dart';
import '../../../core/services/storage_service.dart';
import '../../file_browser/services/local_file_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/device.dart';
import '../services/connection_server.dart';
import '../services/device_service.dart';
import '../services/discovery_service.dart';
import '../services/previously_connected_store.dart';

export '../models/device.dart';
export '../services/connection_server.dart' show ConnectResult, RemoteFileMeta;
export '../services/device_service.dart'
    show DevicePresenceEvent, OutboundDisconnectEvent;

/// 已连接过设备（持久化）
///
/// state 中的 Device 会根据附近设备实时在线状态动态更新 isOnline/ip/name 等字段，
/// 但持久化仅存储稳定字段（id/name/typeIcon/hasPassword）。
///
/// **设计要点**：此 Notifier 内部直接订阅 [DeviceService.presenceChanges] 流，
/// 不依赖任何中间 provider，避免与 [deviceServiceProvider] 形成循环依赖。
final previouslyConnectedDevicesProvider =
    NotifierProvider<PreviouslyConnectedNotifier, List<Device>>(
      PreviouslyConnectedNotifier.new,
    );

class PreviouslyConnectedNotifier extends Notifier<List<Device>> {
  late final PreviouslyConnectedStore _store;
  StreamSubscription<DevicePresenceEvent>? _presenceSub;
  StreamSubscription<OutboundDisconnectEvent>? _outboundSub;

  @override
  List<Device> build() {
    _store = PreviouslyConnectedStore(ref.read(sharedPrefsProvider));

    // 直接订阅 DeviceService 的事件流，避免通过中间 provider 造成循环依赖
    final service = ref.read(deviceServiceProvider);
    _presenceSub = service.presenceChanges.listen(_onPresence);
    _outboundSub = service.outboundDisconnected.listen(_onOutboundDisconnected);

    ref.onDispose(() {
      _presenceSub?.cancel();
      _outboundSub?.cancel();
    });

    return _store.list();
  }

  void _onPresence(DevicePresenceEvent event) {
    final idx = state.indexWhere((d) => d.id == event.deviceId);
    if (idx == -1) return; // 不是已连接过的设备，忽略

    final current = state[idx];
    if (event.isOnline) {
      // 对端刚启动时 deviceInfo 可能尚未加载，beacon 中 name 可能为 "未知设备"。
      // 此时保留已持久化的好名称，避免上线瞬间名称丢失。
      final incomingName = event.device.name;
      final shouldUpdateName =
          incomingName.isNotEmpty && incomingName != '未知设备';
      final newName = shouldUpdateName ? incomingName : current.name;

      // 幂等检查：若设备已在线且关键字段未变化，跳过状态更新（避免每 2s 刷一次）
      if (current.isOnline &&
          current.ip == event.device.ip &&
          current.name == newName &&
          current.hasPassword == event.device.hasPassword) {
        return;
      }

      final updated = List<Device>.from(state);
      updated[idx] = current.copyWith(
        isOnline: true,
        ip: event.device.ip,
        name: newName,
        hasPassword: event.device.hasPassword,
        lastSeenAt: event.device.lastSeenAt,
      );
      state = updated;
      debugPrint(
        '[PrevConnected] 设备上线: ${updated[idx].name} '
        '(${event.device.ip})',
      );

      // 自动连接：已连接过设备上线后，如果连接已开启且当前未连接，自动重连
      _autoConnect(event.device);
    } else {
      // 幂等检查：已经离线则跳过
      if (!current.isOnline) return;
      final updated = List<Device>.from(state);
      updated[idx] = current.copyWith(isOnline: false);
      state = updated;
      debugPrint('[PrevConnected] 设备离线: ${current.name}');
    }
  }

  /// 连接开启后，立刻对所有在线的已连接过设备触发自动重连。
  ///
  /// 解决场景：用户先关闭连接开关（WS 断开、connectionStates 重置为 unconnected），
  /// 再重新打开开关。此时设备的 beacon 仍在持续到达，但 _onPresence 的
  /// 幂等检查会跳过"已在线"设备的状态更新，导致 _autoConnect 不会被触发。
  /// 因此在连接开启后主动遍历一次 state，对仍标记为在线的设备发起自动重连。
  void reconnectAllOnlineWhenEnabled() {
    if (!ref.read(connectionEnabledProvider)) return;
    final targets = state.where((d) => d.isOnline).toList();
    if (targets.isEmpty) return;
    debugPrint('[PrevConnected] 连接已开启，尝试自动重连 ${targets.length} 台在线设备');
    for (final device in targets) {
      _autoConnect(device);
    }
  }

  /// 自动连接已连接过的设备（使用缓存的密码）
  void _autoConnect(Device device) {
    // 连接未开启时不自动连接
    if (!ref.read(connectionEnabledProvider)) return;

    // 已经在连接中或已连接，跳过
    final connState = ref.read(connectionStatesProvider)[device.id];
    if (connState == DeviceConnectionState.connecting ||
        connState == DeviceConnectionState.connected) {
      return;
    }

    debugPrint('[PrevConnected] 自动连接: ${device.name}');

    final service = ref.read(deviceServiceProvider);
    final savedPwd = _store.getPassword(device.id);

    // 设置连接中状态
    ref
        .read(connectionStatesProvider.notifier)
        .set(device.id, DeviceConnectionState.connecting);

    // 异步发起连接
    service.connectToDevice(device, password: savedPwd).then((result) {
      if (result == ConnectResult.success) {
        ref
            .read(connectionStatesProvider.notifier)
            .set(device.id, DeviceConnectionState.connected);
        debugPrint('[PrevConnected] 自动连接成功: ${device.name}');
      } else {
        ref
            .read(connectionStatesProvider.notifier)
            .set(device.id, DeviceConnectionState.unconnected);
        debugPrint('[PrevConnected] 自动连接失败: ${device.name} ($result)');
      }
    });
  }

  void _onOutboundDisconnected(OutboundDisconnectEvent event) {
    final deviceId = event.deviceId;
    // 出站连接断开时取消连接高亮
    ref
        .read(connectionStatesProvider.notifier)
        .set(deviceId, DeviceConnectionState.unconnected);

    // 仅被动断开（对端离线）时才标记离线。
    // 主动断开（用户点击断开 / 移除设备）不改变在线状态，设备仍在线。
    if (!event.isPassive) {
      debugPrint('[PrevConnected] 主动断开，保持在线状态: $deviceId');
      return;
    }

    // 对端离线导致 WS 断开，立即标记离线。
    // 若设备实际仍在线（仍在发 beacon），下个 beacon（≤2s）会重新标记为在线。
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx != -1 && state[idx].isOnline) {
      final updated = List<Device>.from(state);
      updated[idx] = updated[idx].copyWith(isOnline: false);
      state = updated;
      debugPrint(
        '[PrevConnected] 对端离线，立即标记离线: ${updated[idx].name}',
      );
    }
  }

  /// 成功连接后调用
  void onConnected(Device device, {String? password}) {
    _store.add(device, password: password);
    // 用最新的运行时设备信息刷新内存状态（含 isOnline=true）
    state = _store.list().map((d) {
      if (d.id == device.id) {
        return d.copyWith(
          ip: device.ip,
          isOnline: true,
          name: device.name,
          hasPassword: device.hasPassword,
        );
      }
      return d;
    }).toList();
  }

  /// 移除设备（同时清除连接状态 + 断开 WebSocket）
  void remove(String id) {
    _store.remove(id);
    state = _store.list();
    // 清除连接状态 UI
    ref
        .read(connectionStatesProvider.notifier)
        .set(id, DeviceConnectionState.unconnected);
    // 断开 WebSocket 连接
    ref.read(deviceServiceProvider).disconnectDevice(id);
  }

  /// 获取缓存的密码
  String? getPassword(String deviceId) {
    return _store.getPassword(deviceId);
  }
}

/// 设备服务总管
///
/// **依赖关系**：仅依赖全局配置 provider，不依赖
/// [previouslyConnectedDevicesProvider] / [connectionStatesProvider] 的 state，
/// 避免循环依赖。
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final service = DeviceService(
    selfIdGetter: () => ref.read(localDeviceIdProvider),
    selfNameGetter: () {
      final info = ref.read(deviceInfoProvider).value;
      return info?.name ?? '未知设备';
    },
    selfTypeGetter: () {
      final info = ref.read(deviceInfoProvider).value;
      return info?.typeIcon ?? DeviceTypeIcon.web;
    },
    acceptConnectionsGetter: () => ref.read(acceptConnectionsProvider),
    usePasswordGetter: () => ref.read(usePasswordProvider),
    passwordGetter: () => ref.read(connectionPasswordProvider),
    sharedFilesGetter: () async {
      final settings = ref.read(sharedContentProvider);
      final fileService = LocalFileService.instance;
      final files = await fileService.scanFiles(settings);
      return files.map((f) => RemoteFileMeta(
        name: f.name,
        path: f.path,
        size: f.size,
        modifiedAt: f.modifiedAt?.millisecondsSinceEpoch,
      )).toList();
    },
    sharedRootsGetter: () {
      final settings = ref.read(sharedContentProvider);
      return LocalFileService.instance.getSharedRoots(settings);
    },
    thumbnailGetter: (videoPath) {
      return LocalFileService.instance.getVideoThumbnail(videoPath);
    },
  );

  ref.onDispose(service.dispose);
  return service;
});

/// 附近发现的设备（监听 UDP 发现流）
final nearbyDevicesProvider = StreamProvider<List<Device>>((ref) {
  return ref.read(deviceServiceProvider).discoveredDevices;
});

/// 是否正在搜索
final isSearchingDevicesProvider = StreamProvider<bool>((ref) {
  return ref.read(deviceServiceProvider).isSearching;
});

/// 设备在线状态变化流（仅用于调试/扩展，业务同步已在 PreviouslyConnectedNotifier 内部完成）
final devicePresenceProvider = StreamProvider<DevicePresenceEvent>((ref) {
  return ref.read(deviceServiceProvider).presenceChanges;
});

/// 出站连接断开事件流（仅用于调试/扩展，业务同步已在 PreviouslyConnectedNotifier 内部完成）
final outboundDisconnectedProvider =
    StreamProvider<OutboundDisconnectEvent>((ref) {
      return ref.read(deviceServiceProvider).outboundDisconnected;
    });

/// 所有设备的连接状态映射
final connectionStatesProvider =
    NotifierProvider<
      ConnectionStatesNotifier,
      Map<String, DeviceConnectionState>
    >(ConnectionStatesNotifier.new);

class ConnectionStatesNotifier
    extends Notifier<Map<String, DeviceConnectionState>> {
  @override
  Map<String, DeviceConnectionState> build() => const {};

  void set(String deviceId, DeviceConnectionState connState) {
    final next = Map<String, DeviceConnectionState>.from(state);
    next[deviceId] = connState;
    state = next;
  }

  DeviceConnectionState get(String deviceId) =>
      state[deviceId] ?? DeviceConnectionState.unconnected;
}

/// 连接开关状态（持久化，联动 DeviceService）
final connectionEnabledProvider =
    NotifierProvider<ConnectionEnabledNotifier, bool>(
      ConnectionEnabledNotifier.new,
    );

class ConnectionEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref
            .read(sharedPrefsProvider)
            .getBool(StorageKeys.connectionEnabled) ??
        false;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.connectionEnabled, value);
  }
}
