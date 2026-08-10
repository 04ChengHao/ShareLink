import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/global_providers.dart';
import '../../../core/services/device_info_service.dart';
import '../../../core/services/storage_service.dart';
import '../models/device.dart';
import '../services/connection_server.dart';
import '../services/device_service.dart';
import '../services/previously_connected_store.dart';

export '../models/device.dart';
export '../services/connection_server.dart' show ConnectResult;
export '../services/device_service.dart' show DevicePresenceEvent;

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
  StreamSubscription<String>? _outboundSub;

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

    final updated = List<Device>.from(state);
    final current = updated[idx];
    if (event.isOnline) {
      // 对端刚启动时 deviceInfo 可能尚未加载，beacon 中 name 可能为 "未知设备"。
      // 此时保留已持久化的好名称，避免上线瞬间名称丢失。
      final incomingName = event.device.name;
      final shouldUpdateName =
          incomingName.isNotEmpty && incomingName != '未知设备';
      updated[idx] = current.copyWith(
        isOnline: true,
        ip: event.device.ip,
        name: shouldUpdateName ? incomingName : current.name,
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
      updated[idx] = current.copyWith(isOnline: false);
      state = updated;
      debugPrint('[PrevConnected] 设备离线: ${current.name}');
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

  void _onOutboundDisconnected(String deviceId) {
    // 出站连接断开时取消连接高亮
    ref
        .read(connectionStatesProvider.notifier)
        .set(deviceId, DeviceConnectionState.unconnected);

    // WebSocket 断开通常意味着对端已不可达（如关闭 App / 网络中断），
    // 立即标记离线，避免等待 beacon 10s 超时才显示离线。
    // 若设备实际仍在线（仍在发 beacon），下个 beacon（≤2s）会重新标记为在线。
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx != -1 && state[idx].isOnline) {
      final updated = List<Device>.from(state);
      updated[idx] = updated[idx].copyWith(isOnline: false);
      state = updated;
      debugPrint(
        '[PrevConnected] 出站连接断开，立即标记离线: ${updated[idx].name}',
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
final outboundDisconnectedProvider = StreamProvider<String>((ref) {
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
