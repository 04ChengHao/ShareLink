import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/device_info_service.dart';
import '../../../core/services/network_platform_service.dart';
import '../../../core/utils/network_utils.dart';
import '../models/device.dart';

/// UDP 广播发现服务
///
/// 在局域网内通过 UDP 广播 beacon 来发现其他开启享联的设备。
///
/// **Android 特殊处理**：
/// - 需要持有 MulticastLock 才能接收 UDP 广播包（Android WiFi 驱动默认过滤）
/// - Android 12+ 需要位置权限才能通过 network_info_plus 获取 WiFi IP
class DiscoveryService {
  static const int defaultPort = 38381;
  static const Duration _beaconInterval = Duration(seconds: 2);
  static const Duration _offlineTimeout = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _sweepTimer;

  /// 持久化的广播 controller（随服务实例创建，不在 start/stop 中销毁）
  ///
  /// 这样 Riverpod 的 StreamProvider 在 start() 之前订阅时拿到的就是
  /// 真正的流，后续 _notify() 推送的数据能正常到达 UI。
  final StreamController<List<Device>> _controller =
      StreamController<List<Device>>.broadcast();

  final Map<String, Device> _devices = {};

  /// 自身设备 ID（用于过滤回环 beacon）
  String _selfId = '';

  /// 信标中携带的本机信息
  Map<String, dynamic> Function() _beaconBuilder = () => {};

  bool _started = false;

  /// beacon 发送计数（用于降低日志频率）
  int _beaconSendCount = 0;

  /// 缓存的子网广播地址（避免每次发送 beacon 都查询 + 打印日志）
  String? _cachedBroadcastAddr;

  /// 发现新设备时的回调（用于触发 DeviceService 提前结束搜索）
  ///
  /// 仅在新设备首次出现时触发，已发现设备的 beacon 心跳不触发。
  void Function(Device device)? onDeviceDiscovered;

  /// 设备离线/上线时的回调（用于通知 DeviceService 同步已连接过设备状态）
  void Function(Device device, bool isOnline)? onDevicePresenceChanged;

  /// 附近设备全部离线时的回调（用于通知 DeviceService 重新发起一次搜索）
  ///
  /// 当附近设备列表非空、但所有设备都超时离线时触发。
  void Function()? onAllNearbyOffline;

  /// 发现的设备列表流
  Stream<List<Device>> get discoveredDevices => _controller.stream;

  /// 启动发现服务
  Future<void> start({
    required String selfId,
    required Map<String, dynamic> Function() beaconBuilder,
    int port = defaultPort,
  }) async {
    if (_started) return;
    _selfId = selfId;
    _beaconBuilder = beaconBuilder;
    _devices.clear();
    _beaconSendCount = 0;
    _cachedBroadcastAddr = null;

    debugPrint('[Discovery] 启动发现服务, selfId=$selfId, port=$port');

    // Android：先请求位置权限 + 获取 MulticastLock
    if (NetworkPlatformService.isAndroid) {
      debugPrint('[Discovery] Android 平台，请求位置权限...');
      final hasPermission =
          await NetworkPlatformService.requestLocationPermission();
      debugPrint('[Discovery] 位置权限: $hasPermission');

      debugPrint('[Discovery] 获取 MulticastLock...');
      await NetworkPlatformService.acquireMulticastLock();
    }

    try {
      debugPrint('[Discovery] 绑定 UDP socket 到 0.0.0.0:$port ...');
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onDataReceived);
      debugPrint('[Discovery] UDP socket 绑定成功, address=${_socket!.address}');

      // 周期广播 beacon
      _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());
      // 立即发送一次
      _sendBeacon();

      // 定期清理离线设备
      _sweepTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _sweepOffline(),
      );

      _started = true;
      debugPrint('[Discovery] 发现服务启动完成');
    } catch (e) {
      debugPrint('[Discovery] 绑定失败: $e');
      _cleanup();
      rethrow;
    }
  }

  /// 停止发现服务
  ///
  /// 彻底清空附近设备列表（不再保留离线状态），
  /// 因为"附近设备"本身是实时的，关闭服务后不应残留。
  /// 只有"已连接过设备"列表才需要持久化保留。
  Future<void> stop() async {
    debugPrint('[Discovery] 停止发现服务');
    _cleanup();
    _devices.clear();

    // 停止后推送一次空列表，让 UI 清空附近设备
    _notify();

    // Android：释放 MulticastLock
    if (NetworkPlatformService.isAndroid) {
      await NetworkPlatformService.releaseMulticastLock();
    }
  }

  void _cleanup() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
    _started = false;
  }

  /// 发送 UDP 广播 beacon
  Future<void> _sendBeacon() async {
    if (_socket == null) return;
    _beaconSendCount++;

    // 首次发送时查询并缓存广播地址，后续复用（避免每 2s 打印一次 IP 日志）
    _cachedBroadcastAddr ??= await NetworkUtils.getSubnetBroadcastAddress();
    final broadcastAddr = _cachedBroadcastAddr!;

    final beacon = _beaconBuilder();
    final data = utf8.encode(jsonEncode(beacon));
    try {
      _socket!.send(data, InternetAddress(broadcastAddr), defaultPort);
      // 仅第 1 次和每 15 次（约 30s）打印一次，避免日志刷屏
      if (_beaconSendCount == 1 || _beaconSendCount % 15 == 0) {
        debugPrint(
          '[Discovery] beacon 已发送 (#$_beaconSendCount) -> '
          '$broadcastAddr:$defaultPort',
        );
      }
    } catch (e) {
      debugPrint('[Discovery] beacon 发送失败 -> $broadcastAddr: $e');
    }

    // 广播之外，再向所有在线的已发现设备单播一次 beacon。
    // 弥补 AP/Client（热点）拓扑下的广播不对称：本机作为 AP 时广播无法到达
    // Client，若只在发现瞬间单播一次，对端在 ~10s 后会被 sweep 判为离线
    // （即便 WebSocket 连接仍存活）。周期单播让对端持续收到 beacon，保持在线。
    for (final device in _devices.values.toList()) {
      _sendUnicastBeacon(InternetAddress(device.ip));
    }
  }
  ///
  /// 用于修复 AP/Client（热点）拓扑下的广播不对称：当本机作为 Client 时，
  /// AP 的广播 beacon 可能无法到达本机，但既然本机能收到对端的广播，
  /// 说明对端可达。通过单播回应，让对端获得本机（发送方，即 datagram 源）
  /// 的 IP 与名称，从而能反向发现并连接本机。
  void _sendUnicastBeacon(InternetAddress target) {
    if (_socket == null) return;
    final beacon = _beaconBuilder();
    final data = utf8.encode(jsonEncode(beacon));
    try {
      _socket!.send(data, target, defaultPort);
    } catch (e) {
      debugPrint('[Discovery] 单播回应失败 -> ${target.address}: $e');
    }
  }

  /// 接收 UDP 数据
  void _onDataReceived(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _socket?.receive();
      if (datagram == null) return;
      try {
        final json =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        final id = json['id'] as String?;
        if (id == null || id == _selfId) return;

        final existing = _devices[id];
        final wasOnline = existing?.isOnline ?? false;
        final isNewDevice = existing == null;
        final isReappearance = !isNewDevice && !wasOnline;

        final device = Device(
          id: id,
          name: json['name'] as String? ?? '未知设备',
          ip: datagram.address.address,
          typeIcon: _parseTypeIcon(json['typeIcon'] as String?),
          hasPassword: (json['hasPassword'] as bool?) ?? false,
          isOnline: true,
          lastSeenAt: DateTime.now().millisecondsSinceEpoch,
        );

        // 仅在新设备出现或离线设备重新上线时打印日志
        if (isNewDevice) {
          debugPrint(
            '[Discovery] 发现新设备: name=${device.name}, '
            'ip=${device.ip}, id=$id',
          );
        } else if (isReappearance) {
          debugPrint('[Discovery] 设备重新上线: ${device.name} ($id)');
        }

        _devices[id] = device;
        _notify();

        // 向对端单播回传自身 beacon，修复 AP/Client（热点）拓扑下广播不对称：
        // 本机能收到对端的广播，说明对端可达；通过单播回应让对端获得本机的
        // IP 与名称，从而能反向发现并连接本机。只在设备首次出现/重新上线时回应，
        // 避免每次心跳都互相回包造成日志与流量噪音。
        if (isNewDevice || isReappearance) {
          _sendUnicastBeacon(datagram.address);
        }

        // 新设备首次出现时触发搜索回调
        if (isNewDevice) {
          onDeviceDiscovered?.call(device);
        }

        // 始终触发 presence 上线事件。
        // PreviouslyConnectedNotifier 可能因被动 WS 断开将设备标记为离线，
        // 但 beacon 仍在到达说明设备实际在线，需要恢复在线状态。
        // _onPresence 内部会判断是否需要实际更新状态（幂等）。
        onDevicePresenceChanged?.call(device, true);
      } catch (e) {
        debugPrint('[Discovery] 解析 beacon 失败: $e');
      }
    }
  }

  /// 清除本轮搜索中未再发现的残留设备
  ///
  /// 在搜索停止时调用。保留当前在线的设备，移除已离线的设备。
  /// 这样上一轮搜索发现、但本轮未再收到 beacon 的设备会从列表移除。
  void purgeStaleDevices() {
    final before = _devices.length;
    _devices.removeWhere((_, d) => !d.isOnline);
    final after = _devices.length;
    if (before != after) {
      debugPrint('[Discovery] 清除残留设备: $before → $after');
      _notify();
    }
  }

  /// 清理超时离线设备
  ///
  /// 附近设备超时无心跳时直接从列表移除（而非标记离线），
  /// 因为"附近设备"是实时的，离线即代表不再可达。
  /// 当附近设备列表非空、但所有设备都超时离线时，触发 [onAllNearbyOffline] 回调。
  void _sweepOffline() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final offlineThreshold = now - _offlineTimeout.inMilliseconds;
    final removed = <Device>[];

    for (final key in _devices.keys.toList()) {
      final d = _devices[key]!;
      if (d.lastSeenAt < offlineThreshold) {
        _devices.remove(key);
        removed.add(d);
        debugPrint('[Discovery] 设备离线移除: ${d.name} ($key)');
        // 通知 DeviceService 同步已连接过设备状态
        onDevicePresenceChanged?.call(d, false);
      }
    }

    if (removed.isNotEmpty) {
      _notify();
      // 附近设备全部离线时触发回调（仅当之前有设备、现在清空时）
      if (_devices.isEmpty) {
        debugPrint('[Discovery] 附近设备全部离线，通知重新搜索');
        onAllNearbyOffline?.call();
      }
    }
  }

  void _notify() {
    _controller.add(_devices.values.toList());
  }

  DeviceTypeIcon _parseTypeIcon(String? name) {
    if (name == null) return DeviceTypeIcon.web;
    try {
      return DeviceTypeIcon.values.byName(name);
    } catch (_) {
      return DeviceTypeIcon.web;
    }
  }
}
