import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/global_providers.dart';
import '../../../core/utils/permission_utils.dart';
import '../models/file_item.dart';
import 'remote_file_service.dart';

/// 持久下载服务（单例）
///
/// 负责把远程文件持久下载到本地「下载目录」，并按
/// 「设备名/分类名/文件名」分层存放，同时作为缓存被预览/打开复用。
///
/// **目录解析**：
/// - Android：系统 Download/ShareLink
/// - iOS：应用文档目录/ShareLink（系统无下载目录）
/// - 桌面：优先「可执行文件目录/Download」，目录不可写时回退系统下载目录
///
/// **缓存判定**：以 `设备名|文件名|文件大小` 作为键，注册表记录
/// key -> 本地路径；不同分类出现同一文件时复用同一份下载，不重复下载。
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  SharedPreferences? _prefs;

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) throw StateError('DownloadService.init() 未调用');
    return p;
  }

  /// 由 Provider 初始化注入 SharedPreferences
  void init(SharedPreferences prefs) => _prefs = prefs;

  /// 手机端写系统下载目录（/Download/ShareLink）前，确保已授予"所有文件访问"权限。
  ///
  /// Android 11+ 直接写外部 Download 目录需要 MANAGE_EXTERNAL_STORAGE。
  /// 已授权返回 true；Android 未授权则引导跳到系统设置授权并返回 false（本次下载中止，
  /// 避免静默落到应用私有 data 目录）。iOS / 桌面平台无需处理，直接返回 true。
  Future<bool> ensureMobileDownloadPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    return PermissionUtils.requestAllFilesAccess();
  }

  String get _platformSeparator => Platform.pathSeparator;

  // ===========================================================================
  // 目录解析
  // ===========================================================================

  /// 获取下载根目录（若不存在则创建）
  Future<String> getRoot() async {
    if (kIsWeb) {
      final tmp = await getTemporaryDirectory();
      return tmp.path;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[];

    if (Platform.isAndroid) {
      // Android 系统下载目录固定为 /storage/emulated/0/Download
      candidates.add(
        '/storage/emulated/0/Download${_platformSeparator}ShareLink',
      );
    } else if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      candidates.add('${docs.path}${_platformSeparator}ShareLink');
    } else {
      // 桌面：优先安装目录/Download，其次系统下载目录
      candidates.add('$exeDir${_platformSeparator}Download');
      final dl = await getDownloadsDirectory();
      if (dl != null) candidates.add(dl.path);
    }

    for (final c in candidates) {
      if (await _isWritable(c)) {
        await Directory(c).create(recursive: true);
        return c;
      }
    }

    final tmp = await getTemporaryDirectory();
    await Directory(tmp.path).create(recursive: true);
    return tmp.path;
  }

  /// 测试目录是否可写（创建并删除一个探针文件）
  Future<bool> _isWritable(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      await dir.create(recursive: true);
      final probe = File(
        '$dirPath${_platformSeparator}.share_link_probe_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsString('probe');
      await probe.delete();
      return true;
    } catch (e) {
      debugPrint('[Download] 目录不可写: $dirPath -> $e');
      return false;
    }
  }

  // ===========================================================================
  // 路径解析
  // ===========================================================================

  /// 非法文件名字符清洗（文件系统不允许的字符替换为下划线）
  String _sanitize(String name) {
    const illegalWin = ['<', '>', ':', '"', '/', '\\', '|', '?', '*'];
    var result = name;
    for (final c in illegalWin) {
      result = result.replaceAll(c, '_');
    }
    return result.trim().isEmpty ? '_' : result.trim();
  }

  /// 计算缓存键：设备名|文件名|文件大小（跨分类复用）
  String _hashKey(String deviceName, String fileName, int? size) {
    return '${_sanitize(deviceName)}|${_sanitize(fileName)}|$size';
  }

  /// 解析目标绝对路径（root/设备名/分类名/文件名，并创建目录）
  Future<String> resolveTargetPath({
    required String deviceName,
    required String categoryName,
    required String fileName,
  }) async {
    final root = await getRoot();
    final dir = '$root${_platformSeparator}'
        '${_sanitize(deviceName)}${_platformSeparator}'
        '${_sanitize(categoryName)}';
    await Directory(dir).create(recursive: true);
    return '$dir${_platformSeparator}${_sanitize(fileName)}';
  }

  // ===========================================================================
  // 注册表（下载缓存判定）
  // ===========================================================================

  Map<String, String> _readRegistry() {
    final raw = _p.getString(StorageKeys.downloads);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      debugPrint('[Download] 解析注册表失败: $e');
      return const {};
    }
  }

  void _writeRegistry(Map<String, String> map) {
    _p.setString(StorageKeys.downloads, jsonEncode(map));
  }

  void _register(String key, String path) {
    final all = Map<String, String>.from(_readRegistry());
    all[key] = path;
    _writeRegistry(all);
  }

  /// 根据缓存键查找已下载的本地路径（不存在返回 null）
  Future<String?> findCachedFile({
    required String deviceName,
    required String fileName,
    int? size,
  }) async {
    final key = _hashKey(deviceName, fileName, size);
    final p = _readRegistry()[key];
    if (p == null) return null;
    if (File(p).existsSync()) return p;
    return null;
  }

  /// 查询某文件的下载路径（不校验文件是否存在，仅查注册表）
  Future<String?> getDownloadedPath({
    required String deviceName,
    required String fileName,
    int? size,
  }) async {
    final key = _hashKey(deviceName, fileName, size);
    return _readRegistry()[key];
  }

  /// 从下载注册表移除某文件的记录（删除本地下载文件后调用）
  void removeDownloaded({
    required String deviceName,
    required String fileName,
    int? size,
  }) {
    final key = _hashKey(deviceName, fileName, size);
    final all = Map<String, String>.from(_readRegistry());
    if (all.remove(key) != null) {
      _writeRegistry(all);
      debugPrint('[Download] 已移除下载记录: $key');
    }
  }

  /// 移除某设备的所有下载：删除注册表记录并删除其下载目录（用于设备移出后释放空间）
  Future<void> clearForDevice(String deviceName) async {
    final prefix = '${_sanitize(deviceName)}|';
    final all = Map<String, String>.from(_readRegistry());
    final remaining = <String, String>{};
    var removedCount = 0;
    all.forEach((k, v) {
      if (k.startsWith(prefix)) {
        removedCount++;
      } else {
        remaining[k] = v;
      }
    });
    if (removedCount > 0) {
      _writeRegistry(remaining);
    }
    // 删除该设备的下载目录（含已下载文件）
    try {
      final root = await getRoot();
      final dir = Directory(
        '$root${_platformSeparator}${_sanitize(deviceName)}',
      );
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
    if (removedCount > 0) {
      debugPrint('[Download] 已清除设备 $deviceName 的 $removedCount 条下载缓存');
    }
  }

  /// 是否存在某文件的下载记录（供"仅显示下载的文件"筛选）
  ///
  /// [deviceName] 传入当前设备名时只匹配该设备；为 null（浏览本机）时
  /// 匹配任意设备来源的下载记录。
  bool hasDownloadRecord({
    required String? deviceName,
    required String fileName,
    int? size,
  }) {
    final all = _readRegistry();
    if (deviceName != null) {
      final key = _hashKey(deviceName, fileName, size);
      final p = all[key];
      return p != null && File(p).existsSync();
    }
    // 本机：忽略设备前缀，仅按 文件名|大小 匹配
    final suffix = '|${_sanitize(fileName)}|$size';
    return all.entries
        .any((e) => e.key.endsWith(suffix) && File(e.value).existsSync());
  }

  // ===========================================================================
  // 下载
  // ===========================================================================

  /// 下载远程文件到下载目录（持久缓存）
  ///
  /// 已下载（缓存命中）则直接返回本地路径，不做重复下载。
  /// 下载成功后写入注册表，供详情/预览复用。
  ///
  /// [onProgress] 0.0~1.0 进度回调，[onCancel] 返回 true 时中止。
  Future<String?> download({
    required String deviceIp,
    required String deviceName,
    required String categoryName,
    required FileItem file,
    void Function(double progress)? onProgress,
    bool Function()? onCancel,
  }) async {
    final cached = await findCachedFile(
      deviceName: deviceName,
      fileName: file.name,
      size: file.size,
    );
    if (cached != null) {
      debugPrint('[Download] 缓存命中，直接返回: $cached');
      return cached;
    }

    final target = await resolveTargetPath(
      deviceName: deviceName,
      categoryName: categoryName,
      fileName: file.name,
    );

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(RemoteFileService.instance.buildFileUrl(deviceIp, file.path)),
      );
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[Download] 下载失败: ${response.statusCode}');
        return null;
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final dest = File(target);
      final sink = dest.openWrite();
      try {
        await for (final chunk in response) {
          if (onCancel != null && onCancel()) {
            await sink.close();
            try {
              await dest.delete();
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

      _register(
        _hashKey(deviceName, file.name, file.size),
        target,
      );
      return target;
    } catch (e) {
      debugPrint('[Download] 下载异常: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}