import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/app_cache_directory.dart';
import '../models/file_item.dart';
import 'file_cache_service.dart';

/// 远程文件服务
///
/// 负责从远程设备获取文件列表、构建文件访问 URL 和管理临时文件缓存。
///
/// **无缝预览设计**：
/// - 图片：直接通过 HTTP URL 加载（Image.network），无需下载到本地
/// - 视频/音频：直接通过 HTTP URL 流播放（media_kit / libmpv），
///   利用 HTTP Range 请求实现拖拽进度条即时 seek，无需等待完整下载
/// - 文本：通过 HTTP 下载内容（通常很小），缓存在临时目录，定时清理
/// - 不支持的格式：仅显示封面图标，不下载任何内容
///
/// **临时文件管理**：
/// - 临时目录：统一使用全局缓存目录 [AppCacheDirectory]（`share_link_cache/`）
///   与视频缩略图等缓存同目录，便于统一统计大小与清理
/// - 清理策略：每 10 分钟清理一次，删除超过 30 分钟未访问的文件
/// - 应用启动时清空整个全局缓存目录
///
/// **文件列表缓存**：
/// - 通过 [FileCacheService] 持久化到 SharedPreferences
/// - 首次访问：拉取远程列表并缓存
/// - 后续访问：先返回缓存，后台拉取最新列表做增量对比
class RemoteFileService {
  RemoteFileService._();
  static final RemoteFileService instance = RemoteFileService._();

  /// WebSocket/HTTP 文件服务端口（与 ConnectionServer 一致）
  static const int fileServerPort = 38381;

  /// 临时文件最大存活时间
  static const Duration _maxAge = Duration(minutes: 30);

  /// 定时清理间隔
  static const Duration _cleanupInterval = Duration(minutes: 10);

  Timer? _cleanupTimer;

  /// 临时文件访问时间记录：path → 最后访问时间
  final Map<String, DateTime> _accessTimes = {};

  /// 启动定时清理任务
  void startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => cleanupTempFiles());
  }

  /// 停止定时清理任务
  void stopCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// 获取远程文件临时缓存目录路径（统一使用全局缓存目录）
  Future<String> get _tempCacheDir => AppCacheDirectory.path;

  /// 清空整个临时缓存目录（应用启动时调用）
  Future<void> clearAllTempFiles() async {
    try {
      final dirPath = await _tempCacheDir;
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      _accessTimes.clear();
    } catch (e) {
      debugPrint('[RemoteFileService] 清空临时目录失败: $e');
    }
  }

  /// 获取临时缓存目录的总大小（字节）
  Future<int> getTempCacheSize() async {
    try {
      final dirPath = await _tempCacheDir;
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      debugPrint('[RemoteFileService] 获取缓存大小失败: $e');
      return 0;
    }
  }

  /// 清理过期的临时文件
  Future<void> cleanupTempFiles() async {
    try {
      final dirPath = await _tempCacheDir;
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;

      final now = DateTime.now();
      final expiredPaths = <String>[];

      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > _maxAge) {
            expiredPaths.add(entity.path);
          }
        }
      }

      for (final path in expiredPaths) {
        try {
          await File(path).delete();
          _accessTimes.remove(path);
        } catch (_) {}
      }

      if (expiredPaths.isNotEmpty) {
        debugPrint('[RemoteFileService] 清理了 ${expiredPaths.length} 个过期临时文件');
      }
    } catch (e) {
      debugPrint('[RemoteFileService] 清理临时文件失败: $e');
    }
  }

  /// 获取远程文件列表的缓存（无缓存返回 null）
  Future<List<FileItem>?> getCachedFileList(String deviceIp) {
    return FileCacheService.instance.getCachedFiles(deviceIp);
  }

  /// 从远程设备获取文件列表
  ///
  /// [deviceIp] 远程设备 IP 地址
  /// 返回远程设备的共享文件列表
  Future<List<FileItem>> fetchRemoteFileList(String deviceIp) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://$deviceIp:$fileServerPort/filelist'),
      );
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[RemoteFileService] 获取文件列表失败: ${response.statusCode}');
        return [];
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? [];

      final result = files.map((f) {
        final map = f as Map<String, dynamic>;
        return FileItem(
          name: map['name'] as String? ?? '',
          path: map['path'] as String? ?? '',
          size: map['size'] as int?,
          modifiedAt: map['modifiedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int)
              : null,
          isDirectory: false,
        );
      }).toList();

      // 拉取成功后更新本地缓存
      await FileCacheService.instance.saveCache(deviceIp, result);

      return result;
    } catch (e) {
      debugPrint('[RemoteFileService] 获取远程文件列表异常: $e');
      return [];
    }
  }

  /// 构建远程文件的 HTTP 访问 URL
  ///
  /// 用于图片加载、视频/音频流播放
  String buildFileUrl(String deviceIp, String filePath) {
    final encoded = Uri.encodeComponent(filePath);
    return 'http://$deviceIp:$fileServerPort/file?path=$encoded';
  }

  /// 构建远程视频缩略图的 HTTP 访问 URL
  String buildThumbnailUrl(String deviceIp, String filePath) {
    final encoded = Uri.encodeComponent(filePath);
    return 'http://$deviceIp:$fileServerPort/thumb?path=$encoded';
  }

  /// 下载远程文本文件内容
  ///
  /// 对于文本文件，直接通过 HTTP 下载内容并返回字符串。
  /// 不缓存到临时文件（文本文件通常很小，直接缓存在内存中即可）。
  /// 最大文本预览字节数（超过此大小将分块加载，仅预览前 512KB）
  static const int maxTextPreviewBytes = 512 * 1024;

  Future<String?> fetchTextContent(String deviceIp, String filePath) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(buildFileUrl(deviceIp, filePath)),
      );
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[RemoteFileService] 下载文本失败: ${response.statusCode}');
        return null;
      }

      // 分块读取，限制最大预览字节数，避免大文件卡死
      final buffer = <int>[];
      int totalBytes = 0;
      await for (final chunk in response) {
        totalBytes += chunk.length;
        if (totalBytes > maxTextPreviewBytes) {
          // 仅保留前 maxTextPreviewBytes 字节
          final remaining = maxTextPreviewBytes - (totalBytes - chunk.length);
          if (remaining > 0) {
            buffer.addAll(chunk.sublist(0, remaining));
          }
          break;
        }
        buffer.addAll(chunk);
      }
      return utf8.decode(buffer, allowMalformed: true);
    } catch (e) {
      debugPrint('[RemoteFileService] 下载文本内容异常: $e');
      return null;
    }
  }

  /// 下载远程文件到临时目录（用于系统打开方式）
  ///
  /// 仅在用户点击"用系统打开"按钮时才下载完整文件。
  /// 下载后记录访问时间，由定时清理任务管理生命周期。
  ///
  /// [onProgress] 用于回调下载进度（0.0 ~ 1.0），便于 UI 显示加载进度条。
  /// [onCancel] 检查是否已取消，返回 true 时立即中止下载。
  Future<String?> downloadToTemp(
    String deviceIp,
    String filePath, {
    void Function(double progress)? onProgress,
    bool Function()? onCancel,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(buildFileUrl(deviceIp, filePath)),
      );
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final dirPath = await _tempCacheDir;
      // 远程路径可能使用 / 或 \，统一处理两种分隔符以正确提取文件名
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      final tempPath = '$dirPath${Platform.pathSeparator}${fileName.hashCode}_$fileName';

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final file = File(tempPath);
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          if (onCancel != null && onCancel()) {
            await sink.close();
            try {
              await file.delete();
            } catch (_) {}
            return null;
          }
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            onProgress(receivedBytes / totalBytes);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      _accessTimes[tempPath] = DateTime.now();
      return tempPath;
    } catch (e) {
      debugPrint('[RemoteFileService] 下载文件到临时目录异常: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
