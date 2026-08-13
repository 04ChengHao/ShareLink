import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/device_info_service.dart';

/// 连接结果类型
enum ConnectResult { success, authFailed, rejected, networkError, timeout }

/// 远程文件元数据（用于文件列表响应）
class RemoteFileMeta {
  final String name;
  final String path;
  final int? size;
  final int? modifiedAt;

  const RemoteFileMeta({
    required this.name,
    required this.path,
    this.size,
    this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'size': size,
    'modifiedAt': modifiedAt,
  };
}

/// WebSocket 服务端（dart:io）
///
/// 同时承担两个职责：
/// 1. WebSocket 握手与连接管理（端口 38381）
/// 2. HTTP 文件服务（同端口，非 WebSocket 请求路由到文件处理器）
///    - GET /filelist → 返回共享文件列表 JSON
///    - GET /file?path=... → 返回文件内容（支持 Range 请求，用于视频/音频流播放）
///    - GET /thumb?path=... → 返回视频缩略图
class ConnectionServer {
  static const int defaultPort = 38381;

  HttpServer? _server;
  final Map<String, WebSocket> _inbound = {};

  /// 已连接的对端 IP 集合（用于 HTTP 文件服务访问控制）
  final Set<String> _connectedPeerIps = {};

  /// 回调：是否接受连接
  final bool Function() _acceptConnectionsGetter;

  /// 回调：是否启用密码
  final bool Function() _usePasswordGetter;

  /// 回调：获取密码
  final String Function() _passwordGetter;

  /// 回调：获取共享文件列表（用于 /filelist 端点）
  final Future<List<RemoteFileMeta>> Function()? _getSharedFilesGetter;

  /// 回调：获取共享文件夹根路径列表（用于文件访问安全校验）
  final List<String> Function()? _getSharedRootsGetter;

  /// 回调：获取视频缩略图路径（用于 /thumb 端点）
  final Future<String?> Function(String videoPath)? _getThumbnailGetter;

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
    Future<List<RemoteFileMeta>> Function()? getSharedFilesGetter,
    List<String> Function()? getSharedRootsGetter,
    Future<String?> Function(String videoPath)? getThumbnailGetter,
    this.onPeerConnected,
    this.onPeerDisconnected,
  }) : _acceptConnectionsGetter = acceptConnectionsGetter,
       _usePasswordGetter = usePasswordGetter,
       _passwordGetter = passwordGetter,
       _getSharedFilesGetter = getSharedFilesGetter,
       _getSharedRootsGetter = getSharedRootsGetter,
       _getThumbnailGetter = getThumbnailGetter;

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
    _connectedPeerIps.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('[ConnectionServer] 服务端已停止');
  }

  /// 处理 HTTP 请求（WebSocket 升级 + 文件服务）
  Future<void> _handleRequest(HttpRequest request) async {
    // WebSocket 升级请求 → 走 WebSocket 握手流程
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      await _handleWebSocketRequest(request);
      return;
    }

    // 普通 HTTP 请求 → 文件服务
    await _handleFileHttpRequest(request);
  }

  // ===========================================================================
  // WebSocket 握手
  // ===========================================================================

  Future<void> _handleWebSocketRequest(HttpRequest request) async {
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
      final peerIp = request.connectionInfo?.remoteAddress.address ?? '';

      debugPrint('[ConnectionServer] 握手成功，发送 auth_ok: $peerName');
      ws.add(jsonEncode({'type': 'auth_ok'}));
      _inbound[peerId] = ws;
      _connectedPeerIps.add(peerIp);

      // 后续消息监听（复用同一个广播流）
      broadcastStream.listen(
        (data) {
          // 后续消息处理（剪贴板/文件等，本期暂不处理）
        },
        onError: (_) {
          _inbound.remove(peerId);
          _connectedPeerIps.remove(peerIp);
          onPeerDisconnected?.call(peerId);
        },
        onDone: () {
          _inbound.remove(peerId);
          _connectedPeerIps.remove(peerIp);
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

  // ===========================================================================
  // HTTP 文件服务（供远程设备预览文件）
  // ===========================================================================

  /// 处理文件 HTTP 请求
  ///
  /// 端点：
  /// - GET /filelist → 共享文件列表 JSON
  /// - GET /file?path=... → 文件内容（支持 Range）
  /// - GET /thumb?path=... → 视频缩略图
  Future<void> _handleFileHttpRequest(HttpRequest request) async {
    try {
      // 访问控制：仅允许已建立 WebSocket 连接的对端 IP
      final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
      if (!_connectedPeerIps.contains(remoteIp)) {
        debugPrint('[FileServer] 拒绝未连接 IP 的文件请求: $remoteIp');
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      switch (path) {
        case '/filelist':
          await _handleFileListRequest(request);
          break;
        case '/file':
          await _handleFileServingRequest(request);
          break;
        case '/thumb':
          await _handleThumbnailRequest(request);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (e) {
      debugPrint('[FileServer] 处理文件请求异常: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  /// 处理文件列表请求
  Future<void> _handleFileListRequest(HttpRequest request) async {
    if (_getSharedFilesGetter == null) {
      request.response.statusCode = HttpStatus.notImplemented;
      await request.response.close();
      return;
    }

    final files = await _getSharedFilesGetter!();
    final json = jsonEncode({
      'type': 'file_list',
      'files': files.map((f) => f.toJson()).toList(),
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(json);
    await request.response.close();
  }

  /// 处理文件内容请求（支持 Range，用于视频/音频流播放）
  Future<void> _handleFileServingRequest(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    if (filePath == null || filePath.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    // 安全校验：文件必须在共享根目录下
    if (!_isPathAllowed(filePath)) {
      debugPrint('[FileServer] 拒绝访问非共享路径: $filePath');
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileSize = await file.length();

    // 解析 Range 请求头
    final rangeHeader = request.headers.value('range');
    int start = 0;
    int end = fileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final ranges = rangeHeader.substring(6).split('-');
      if (ranges.isNotEmpty && ranges[0].isNotEmpty) {
        start = int.parse(ranges[0]);
      }
      if (ranges.length > 1 && ranges[1].isNotEmpty) {
        end = int.parse(ranges[1]);
      }
      // 范围越界保护
      if (start >= fileSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.add('Content-Range', 'bytes */$fileSize');
        await request.response.close();
        return;
      }
      if (end >= fileSize) end = fileSize - 1;
    }

    final contentLength = end - start + 1;

    // 设置响应头
    request.response.statusCode = rangeHeader != null
        ? HttpStatus.partialContent
        : HttpStatus.ok;
    request.response.headers.contentType = _getContentType(filePath);
    request.response.headers.add('Accept-Ranges', 'bytes');
    request.response.headers.add('Content-Length', contentLength);
    if (rangeHeader != null) {
      request.response.headers.add(
        'Content-Range',
        'bytes $start-$end/$fileSize',
      );
    }

    // 流式写入文件内容
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(start);
      int remaining = contentLength;
      const chunkSize = 64 * 1024; // 64KB chunks
      while (remaining > 0) {
        final read = (remaining > chunkSize ? chunkSize : remaining);
        final data = await raf.read(read);
        if (data.isEmpty) break;
        request.response.add(data);
        remaining -= data.length;
      }
      await request.response.close();
    } catch (e) {
      debugPrint('[FileServer] 流式写入失败: $e');
      await request.response.close();
    } finally {
      await raf.close();
    }
  }

  /// 处理视频缩略图请求
  Future<void> _handleThumbnailRequest(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    if (filePath == null || filePath.isEmpty || _getThumbnailGetter == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    if (!_isPathAllowed(filePath)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final thumbPath = await _getThumbnailGetter!(filePath);
    if (thumbPath == null || !File(thumbPath).existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final thumbFile = File(thumbPath);
    final fileSize = await thumbFile.length();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.parse('image/jpeg');
    request.response.headers.add('Content-Length', fileSize);
    await request.response.addStream(thumbFile.openRead());
    await request.response.close();
  }

  /// 校验文件路径是否在共享根目录下（防止路径穿越攻击）
  bool _isPathAllowed(String filePath) {
    if (_getSharedRootsGetter == null) return false;
    final roots = _getSharedRootsGetter!();
    if (roots.isEmpty) return false;

    final normalizedPath = File(filePath).absolute.path;
    for (final root in roots) {
      final normalizedRoot = Directory(root).absolute.path;
      if (normalizedPath.startsWith(normalizedRoot)) {
        return true;
      }
    }
    return false;
  }

  /// 根据文件扩展名获取 Content-Type
  ContentType _getContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return ContentType.parse('image/jpeg');
      case 'png':
        return ContentType.parse('image/png');
      case 'gif':
        return ContentType.parse('image/gif');
      case 'webp':
        return ContentType.parse('image/webp');
      case 'bmp':
        return ContentType.parse('image/bmp');
      case 'svg':
        return ContentType.parse('image/svg+xml');
      case 'mp4':
        return ContentType.parse('video/mp4');
      case 'mkv':
        return ContentType.parse('video/x-matroska');
      case 'avi':
        return ContentType.parse('video/x-msvideo');
      case 'mov':
        return ContentType.parse('video/quicktime');
      case 'wmv':
        return ContentType.parse('video/x-ms-wmv');
      case 'flv':
        return ContentType.parse('video/x-flv');
      case 'ts':
        return ContentType.parse('video/mp2t');
      case '3gp':
        return ContentType.parse('video/3gpp');
      case 'mp3':
        return ContentType.parse('audio/mpeg');
      case 'wav':
        return ContentType.parse('audio/wav');
      case 'flac':
        return ContentType.parse('audio/flac');
      case 'aac':
        return ContentType.parse('audio/aac');
      case 'ogg':
        return ContentType.parse('audio/ogg');
      case 'm4a':
        return ContentType.parse('audio/mp4');
      case 'wma':
        return ContentType.parse('audio/x-ms-wma');
      case 'txt':
      case 'md':
      case 'log':
        return ContentType.parse('text/plain; charset=utf-8');
      case 'csv':
        return ContentType.parse('text/csv; charset=utf-8');
      default:
        return ContentType.binary;
    }
  }
}
