import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/device_info_service.dart';
import '../models/device.dart';
import 'connection_client.dart';
import 'connection_server.dart';
import 'discovery_service.dart';

/// 权限异常
class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
  @override
  String toString() => 'PermissionException: $message';
}

/// 搜索超时时长：最长搜索 10 秒（无任何设备时自动停止）
const Duration _searchMaxTimeout = Duration(seconds: 10);

/// 发现新设备后的静默倒计时：3 秒内无新设备则结束搜索
///
/// 每次发现新设备都会刷新此倒计时。
const Duration _searchGraceAfterDevice = Duration(seconds: 3);

/// 服务总管：组合 DiscoveryService + ConnectionServer + ConnectionClient
class DeviceService {
  final DiscoveryService _discovery = DiscoveryService();
  late final ConnectionServer _server;
  final ConnectionClient _client = ConnectionClient();

  /// getter 回调：读取 Riverpod 设置（避免捕获旧值）
  final String Function() _selfIdGetter;
  final String Function() _selfNameGetter;
  final DeviceTypeIcon Function() _selfTypeGetter;
  final bool Function() _acceptConnectionsGetter;
  final bool Function() _usePasswordGetter;
  final String Function() _passwordGetter;

  bool _started = false;

  /// 当前是否处于搜索中状态
  bool _isSearching = false;

  /// 最大搜索超时计时器（10s）
  Timer? _searchMaxTimer;

  /// 发现新设备后的静默倒计时（3s，每次新设备刷新）
  Timer? _graceTimer;

  final StreamController<bool> _searchingController =
      StreamController<bool>.broadcast();

  /// 设备在线状态变化流（用于同步"已连接过设备"的在线状态）
  ///
  /// 推送 (deviceId, isOnline) 元组
  final StreamController<DevicePresenceEvent> _presenceController =
      StreamController<DevicePresenceEvent>.broadcast();

  /// 出站连接断开事件流（用于 UI 取消连接高亮）
  ///
  /// 推送 (deviceId, isPassive) 元组：
  /// - isPassive=true：对端离线导致的被动断开
  /// - isPassive=false：本端主动调用 disconnect
  final StreamController<OutboundDisconnectEvent> _outboundDisconnectedController =
      StreamController<OutboundDisconnectEvent>.broadcast();

  StreamSubscription? _discoverySub;

  DeviceService({
    required String Function() selfIdGetter,
    required String Function() selfNameGetter,
    required DeviceTypeIcon Function() selfTypeGetter,
    required bool Function() acceptConnectionsGetter,
    required bool Function() usePasswordGetter,
    required String Function() passwordGetter,
  }) : _selfIdGetter = selfIdGetter,
       _selfNameGetter = selfNameGetter,
       _selfTypeGetter = selfTypeGetter,
       _acceptConnectionsGetter = acceptConnectionsGetter,
       _usePasswordGetter = usePasswordGetter,
       _passwordGetter = passwordGetter {
    _server = ConnectionServer(
      acceptConnectionsGetter: _acceptConnectionsGetter,
      usePasswordGetter: _usePasswordGetter,
      passwordGetter: _passwordGetter,
    );

    // 注册 Discovery 回调
    _discovery.onDeviceDiscovered = _onFirstDeviceDiscovered;
    _discovery.onDevicePresenceChanged = _onPresenceChanged;
    _discovery.onAllNearbyOffline = _onAllNearbyOffline;

    // 注册 ConnectionClient 断连回调
    _client.onDisconnected = _onOutboundDisconnected;
  }

  /// 发现的设备列表流
  Stream<List<Device>> get discoveredDevices => _discovery.discoveredDevices;

  /// 是否正在搜索
  Stream<bool> get isSearching => _searchingController.stream;

  /// 设备在线状态变化流
  Stream<DevicePresenceEvent> get presenceChanges => _presenceController.stream;

  /// 出站连接断开事件流
  Stream<OutboundDisconnectEvent> get outboundDisconnected =>
      _outboundDisconnectedController.stream;

  /// 启动所有服务
  Future<void> start() async {
    if (_started) {
      debugPrint('[DeviceService] 服务已启动，跳过');
      return;
    }

    // Web 平台不支持 dart:io
    if (kIsWeb) {
      _started = true;
      return;
    }

    debugPrint('[DeviceService] 正在启动服务...');

    try {
      // 启动发现服务
      await _discovery.start(
        selfId: _selfIdGetter(),
        beaconBuilder: _buildBeacon,
      );

      // 启动 WebSocket 服务端
      await _server.start();
      debugPrint('[DeviceService] WebSocket 服务端已启动 (port=38381)');

      _started = true;
      _startSearching();
      debugPrint('[DeviceService] 服务启动完成，开始搜索（最长 10s）');
    } catch (e) {
      debugPrint('[DeviceService] 服务启动失败: $e');
      _setSearching(false);
      throw PermissionException('无法启动服务，请检查网络权限: $e');
    }
  }

  /// 刷新搜索（重新开始搜索计时，并清除上一次残留设备）
  Future<void> refresh() async {
    if (!_started) {
      debugPrint('[DeviceService] 服务未启动，调用 start() 代替 refresh()');
      return start();
    }
    debugPrint('[DeviceService] 刷新搜索');
    _startSearching();
  }

  /// 仅重启发现服务（UDP socket），不中断已建立的 WebSocket 连接
  ///
  /// 用于手机从后台恢复前台时，重新绑定 UDP socket 以恢复 beacon 接收，
  /// 同时保持所有已建立的 WebSocket 连接不变。
  Future<void> restartDiscovery() async {
    if (!_started) {
      debugPrint('[DeviceService] 服务未启动，调用 start() 代替 restartDiscovery()');
      return start();
    }
    if (kIsWeb) return;
    debugPrint('[DeviceService] 重启发现服务（保持 WebSocket 连接）');
    await _discovery.stop();
    await _discovery.start(
      selfId: _selfIdGetter(),
      beaconBuilder: _buildBeacon,
    );
    _startSearching();
  }

  /// 开始搜索状态
  ///
  /// 搜索逻辑：
  /// - 启动 10s 最大超时计时器，无任何设备时 10s 后自动停止
  /// - 每次发现新设备时启动/刷新 3s 静默倒计时，3s 内无新设备则停止搜索
  /// - 停止搜索后清除本轮未再发现的残留设备
  void _startSearching() {
    _searchMaxTimer?.cancel();
    _graceTimer?.cancel();
    _graceTimer = null;
    _isSearching = true;
    _setSearching(true);

    _searchMaxTimer = Timer(_searchMaxTimeout, () {
      debugPrint('[DeviceService] 搜索超时（10s 最大时长），停止搜索状态');
      _stopSearching();
    });
  }

  /// DiscoveryService 回调：发现新设备
  ///
  /// 每次 discovery 通知新设备都会刷新 3s 静默倒计时。
  void _onFirstDeviceDiscovered(Device device) {
    if (!_isSearching) return;
    debugPrint('[DeviceService] 发现设备 ${device.name}，刷新 3s 静默倒计时');
    _graceTimer?.cancel();
    _graceTimer = Timer(_searchGraceAfterDevice, () {
      debugPrint('[DeviceService] 3s 内无新设备，停止搜索状态');
      _stopSearching();
    });
  }

  /// 停止搜索状态并清除本轮残留设备
  void _stopSearching() {
    if (!_isSearching) return;
    _searchMaxTimer?.cancel();
    _searchMaxTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _isSearching = false;
    _setSearching(false);
    // 清除本轮搜索中未再发现的残留设备
    _discovery.purgeStaleDevices();
  }

  /// DiscoveryService 回调：设备在线状态变化
  void _onPresenceChanged(Device device, bool isOnline) {
    _presenceController.add(
      DevicePresenceEvent(
        deviceId: device.id,
        isOnline: isOnline,
        device: device,
      ),
    );
  }

  /// DiscoveryService 回调：附近设备全部离线
  ///
  /// 清空附近设备列表后自动开启一次新的搜索（仅当服务已启动且当前不在搜索中时）。
  void _onAllNearbyOffline() {
    if (!_started) return;
    if (_isSearching) {
      debugPrint('[DeviceService] 附近设备全部离线，但已在搜索中，跳过');
      return;
    }
    debugPrint('[DeviceService] 附近设备全部离线，自动重新搜索');
    _startSearching();
  }

  /// ConnectionClient 回调：出站连接断开
  void _onOutboundDisconnected(String deviceId, bool isPassive) {
    debugPrint(
      '[DeviceService] 出站连接断开: $deviceId (passive=$isPassive)',
    );
    _outboundDisconnectedController.add(
      OutboundDisconnectEvent(deviceId: deviceId, isPassive: isPassive),
    );
  }

  /// 停止所有服务
  Future<void> stop() async {
    if (!_started) return;
    debugPrint('[DeviceService] 停止所有服务');
    _searchMaxTimer?.cancel();
    _searchMaxTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _isSearching = false;
    _setSearching(false);
    await _discovery.stop();
    await _server.stop();
    await _client.disconnectAll();
    _started = false;
  }

  /// 连接到指定设备
  Future<ConnectResult> connectToDevice(
    Device device, {
    String? password,
  }) async {
    debugPrint('[DeviceService] 连接设备: ${device.name} (${device.ip})');
    if (kIsWeb) return ConnectResult.networkError;

    return _client.connect(
      device: device,
      selfId: _selfIdGetter(),
      selfName: _selfNameGetter(),
      selfType: _selfTypeGetter(),
      password: password,
    );
  }

  /// 断开指定设备
  Future<void> disconnectDevice(String deviceId) async {
    await _client.disconnect(deviceId);
  }

  /// 构建 beacon 数据
  Map<String, dynamic> _buildBeacon() {
    return {
      'v': 1,
      'id': _selfIdGetter(),
      'name': _selfNameGetter(),
      'typeIcon': _selfTypeGetter().name,
      'hasPassword': _usePasswordGetter() && _passwordGetter().isNotEmpty,
      'wsPort': 38381,
    };
  }

  void _setSearching(bool value) {
    _searchingController.add(value);
  }

  void dispose() {
    _searchMaxTimer?.cancel();
    _graceTimer?.cancel();
    _discoverySub?.cancel();
    _searchingController.close();
    _presenceController.close();
    _outboundDisconnectedController.close();
  }
}

/// 设备在线状态变化事件
class DevicePresenceEvent {
  final String deviceId;
  final bool isOnline;

  /// 最新的设备信息（包含最新 IP、name 等）
  final Device device;

  const DevicePresenceEvent({
    required this.deviceId,
    required this.isOnline,
    required this.device,
  });
}

/// 出站连接断开事件
class OutboundDisconnectEvent {
  final String deviceId;

  /// true = 对端离线导致的被动断开；false = 本端主动断开
  final bool isPassive;

  const OutboundDisconnectEvent({
    required this.deviceId,
    required this.isPassive,
  });
}
