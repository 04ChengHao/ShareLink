import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../../../core/services/device_info_service.dart';
import '../models/device.dart';
import 'connection_server.dart';

/// WebSocket 客户端
class ConnectionClient {
  static const Duration _defaultTimeout = Duration(seconds: 5);

  final Map<String, IOWebSocketChannel> _outbound = {};
  final Map<String, Future<ConnectResult>> _pending = {};

  /// 出站连接断开回调（deviceId）
  void Function(String deviceId)? onDisconnected;

  /// 发起 WebSocket 连接
  Future<ConnectResult> connect({
    required Device device,
    required String selfId,
    required String selfName,
    required DeviceTypeIcon selfType,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    // 同设备进行中的连接复用
    if (_pending.containsKey(device.id)) {
      debugPrint('[ConnectionClient] 设备 ${device.name} 已有进行中的连接，复用');
      return _pending[device.id]!;
    }

    final future = _doConnect(
      device: device,
      selfId: selfId,
      selfName: selfName,
      selfType: selfType,
      password: password,
      timeout: timeout,
    );
    _pending[device.id] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pending.remove(device.id);
    }
  }

  Future<ConnectResult> _doConnect({
    required Device device,
    required String selfId,
    required String selfName,
    required DeviceTypeIcon selfType,
    String? password,
    required Duration timeout,
  }) async {
    IOWebSocketChannel? channel;
    try {
      debugPrint(
        '[ConnectionClient] 正在连接 ws://${device.ip}:38381 '
        '(设备: ${device.name})',
      );

      channel = IOWebSocketChannel.connect(
        Uri.parse('ws://${device.ip}:38381'),
        connectTimeout: timeout,
      );

      // 发送 hello 握手
      final hello = {
        'type': 'hello',
        'id': selfId,
        'name': selfName,
        'typeIcon': selfType.name,
        if (password != null) 'password': password,
      };
      debugPrint('[ConnectionClient] 发送 hello: id=$selfId, name=$selfName');
      channel.sink.add(jsonEncode(hello));

      // 将单订阅流转换为广播流，允许握手阶段和后续监听阶段各自 listen
      final broadcastStream = channel.stream.asBroadcastStream();

      // 等待第一条响应
      final completer = Completer<ConnectResult>();
      late StreamSubscription sub;
      sub = broadcastStream.listen(
        (data) {
          debugPrint('[ConnectionClient] 收到响应: $data');
          if (!completer.isCompleted) {
            try {
              final json = jsonDecode(data as String) as Map<String, dynamic>;
              final type = json['type'] as String?;
              switch (type) {
                case 'auth_ok':
                  _outbound[device.id] = channel!;
                  completer.complete(ConnectResult.success);
                  break;
                case 'auth_failed':
                  completer.complete(ConnectResult.authFailed);
                  break;
                case 'rejected':
                  completer.complete(ConnectResult.rejected);
                  break;
                default:
                  debugPrint('[ConnectionClient] 未知响应类型: $type');
                  completer.complete(ConnectResult.networkError);
              }
            } catch (e) {
              debugPrint('[ConnectionClient] 解析响应失败: $e');
              completer.complete(ConnectResult.networkError);
            }
          }
        },
        onError: (e) {
          debugPrint('[ConnectionClient] stream onError: $e');
          if (!completer.isCompleted) {
            completer.complete(ConnectResult.networkError);
          }
        },
        onDone: () {
          debugPrint('[ConnectionClient] stream onDone (连接关闭)');
          if (!completer.isCompleted) {
            completer.complete(ConnectResult.networkError);
          }
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(timeout);
      await sub.cancel();
      debugPrint('[ConnectionClient] 连接结果: $result (${device.name})');

      // 非成功时关闭 channel
      if (result != ConnectResult.success) {
        await channel.sink.close();
        return result;
      }

      // 成功建立连接后，持续监听断开事件（复用同一个广播流）
      broadcastStream.listen(
        (_) {
          // 后续业务消息（暂不处理）
        },
        onError: (e) {
          debugPrint('[ConnectionClient] 连接断开(错误): ${device.name} - $e');
          _outbound.remove(device.id);
          onDisconnected?.call(device.id);
        },
        onDone: () {
          debugPrint('[ConnectionClient] 连接断开(完成): ${device.name}');
          _outbound.remove(device.id);
          onDisconnected?.call(device.id);
        },
        cancelOnError: true,
      );

      return result;
    } catch (e) {
      debugPrint('[ConnectionClient] 连接异常: ${device.name} - $e');
      await channel?.sink.close();
      if (e is TimeoutException) return ConnectResult.timeout;
      return ConnectResult.networkError;
    }
  }

  /// 断开指定设备连接
  Future<void> disconnect(String deviceId) async {
    final channel = _outbound.remove(deviceId);
    await channel?.sink.close();
  }

  /// 指定设备是否已连接
  bool isConnected(String deviceId) => _outbound.containsKey(deviceId);

  /// 关闭所有出站连接
  Future<void> disconnectAll() async {
    final channels = _outbound.values.toList();
    _outbound.clear();
    for (final ch in channels) {
      await ch.sink.close();
    }
  }
}
