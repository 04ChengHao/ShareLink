import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/device_info_service.dart';

/// 连接结果类型
enum ConnectResult { success, authFailed, rejected, networkError, timeout }

/// WebSocket 服务端（dart:io）
class ConnectionServer {
  static const int defaultPort = 38381;

  HttpServer? _server;
  final Map<String, WebSocket> _inbound = {};

  /// 回调：是否接受连接
  final bool Function() _acceptConnectionsGetter;

  /// 回调：是否启用密码
  final bool Function() _usePasswordGetter;

  /// 回调：获取密码
  final String Function() _passwordGetter;

  /// 回调：对端连接成功
  final void Function(
    String peerId,
    String peerName,
    DeviceTypeIcon peerType,
    WebSocket socket,
  )?
  onPeerConnected;

  /// 回调：对端断开
  final void Function(String peerId)? onPeerDisconnected;

  ConnectionServer({
    required bool Function() acceptConnectionsGetter,
    required bool Function() usePasswordGetter,
    required String Function() passwordGetter,
    this.onPeerConnected,
    this.onPeerDisconnected,
  }) : _acceptConnectionsGetter = acceptConnectionsGetter,
       _usePasswordGetter = usePasswordGetter,
       _passwordGetter = passwordGetter;

  /// 启动 WebSocket 服务端
  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);
      debugPrint(
        '[ConnectionServer] WebSocket 服务端已启动，监听 ${_server!.address.address}:$port',
      );
    } catch (e) {
      _server = null;
      debugPrint('[ConnectionServer] 启动失败: $e');
      rethrow;
    }
  }

  /// 停止服务端
  Future<void> stop() async {
    for (final ws in _inbound.values) {
      await ws.close(1001, 'server shutting down');
    }
    _inbound.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('[ConnectionServer] 服务端已停止');
  }

  /// 处理 HTTP 升级请求
  Future<void> _handleRequest(HttpRequest request) async {
    debugPrint(
      '[ConnectionServer] 收到 HTTP 请求: ${request.method} ${request.uri} '
      'from ${request.connectionInfo?.remoteAddress.address}',
    );

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      debugPrint('[ConnectionServer] 非 WebSocket 升级请求，拒绝');
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e) {
      debugPrint('[ConnectionServer] WebSocket 升级失败: $e');
      return;
    }
    debugPrint('[ConnectionServer] WebSocket 升级成功');

    // 将单订阅流转换为广播流，允许握手阶段和后续监听阶段各自 listen
    final broadcastStream = ws.asBroadcastStream();

    final completer = Completer<Map<String, dynamic>>();

    // 等待第一条消息（hello 握手）
    late StreamSubscription sub;
    sub = broadcastStream.listen(
      (data) {
        if (!completer.isCompleted) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            completer.complete(json);
          } catch (_) {
            completer.completeError('parse error');
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.completeError('closed');
      },
      cancelOnError: true,
    );

    try {
      final hello = await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      debugPrint('[ConnectionServer] 收到 hello: ${hello['name']}');

      final type = hello['type'] as String?;
      if (type != 'hello') {
        debugPrint('[ConnectionServer] 无效握手类型: $type');
        _sendAndClose(ws, {'type': 'rejected', 'reason': 'invalid_handshake'});
        return;
      }

      // 检查是否接受连接
      final accepting = _acceptConnectionsGetter();
      if (!accepting) {
        debugPrint('[ConnectionServer] 拒绝连接（未开启接受连接）');
        _sendAndClose(ws, {'type': 'rejected', 'reason': 'not_accepting'});
        return;
      }

      // 检查密码
      if (_usePasswordGetter()) {
        final pwd = hello['password'] as String? ?? '';
        if (pwd != _passwordGetter()) {
          debugPrint('[ConnectionServer] 密码错误');
          _sendAndClose(ws, {'type': 'auth_failed'});
          return;
        }
      }

      // 握手成功
      final peerId = hello['id'] as String? ?? 'unknown';
      final peerName = hello['name'] as String? ?? '未知设备';
      final peerType = _parseTypeIcon(hello['typeIcon'] as String?);

      debugPrint('[ConnectionServer] 握手成功，发送 auth_ok: $peerName');
      ws.add(jsonEncode({'type': 'auth_ok'}));
      _inbound[peerId] = ws;

      // 后续消息监听（复用同一个广播流）
      broadcastStream.listen(
        (data) {
          // 后续消息处理（剪贴板/文件等，本期暂不处理）
        },
        onError: (_) {
          _inbound.remove(peerId);
          onPeerDisconnected?.call(peerId);
        },
        onDone: () {
          _inbound.remove(peerId);
          onPeerDisconnected?.call(peerId);
        },
        cancelOnError: true,
      );

      onPeerConnected?.call(peerId, peerName, peerType, ws);
    } catch (e) {
      debugPrint('[ConnectionServer] 握手异常: $e');
      await sub.cancel();
      await ws.close(1001, 'handshake timeout');
    }
  }

  void _sendAndClose(WebSocket ws, Map<String, dynamic> msg) {
    ws.add(jsonEncode(msg));
    ws.close(4001, msg['type'] as String);
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
