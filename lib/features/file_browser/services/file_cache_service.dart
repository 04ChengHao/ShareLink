import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';

/// 远程文件元数据本地缓存服务
///
/// 用于缓存从远程设备获取的文件列表，避免每次切换设备时都全量扫描。
/// - **首次访问**：从远程设备拉取文件列表，缓存到本地
/// - **后续访问**：先返回缓存数据立即可用，后台再拉取最新列表做增量对比
/// - **变更检测**：通过对比 `uniqueKey`（路径+大小+修改时间）判断是否需要更新
///
/// 缓存结构（按设备 IP 隔离）：
/// ```
/// {
///   "192.168.1.100": {
///     "files": [...],
///     "lastSyncAt": 1718000000000
///   }
/// }
/// ```
class FileCacheService {
  FileCacheService._();
  static final FileCacheService instance = FileCacheService._();

  static const String _cacheKeyPrefix = 'remote_file_cache_';

  /// 获取指定设备的缓存文件列表（无缓存返回 null）
  Future<List<FileItem>?> getCachedFiles(String deviceIp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_cacheKeyPrefix$deviceIp');
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? [];
      return files
          .map((f) => _fileItemFromJson(f as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[FileCacheService] 读取缓存失败: $e');
      return null;
    }
  }

  /// 获取指定设备的最后同步时间（无缓存返回 null）
  Future<DateTime?> getLastSyncTime(String deviceIp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_cacheKeyPrefix$deviceIp');
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final ts = json['lastSyncAt'] as int?;
      return ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// 保存文件列表到缓存（更新同步时间）
  Future<void> saveCache(String deviceIp, List<FileItem> files) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode({
        'files': files.map((f) => _fileItemToJson(f)).toList(),
        'lastSyncAt': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString('$_cacheKeyPrefix$deviceIp', jsonStr);
    } catch (e) {
      debugPrint('[FileCacheService] 保存缓存失败: $e');
    }
  }

  /// 清除指定设备的缓存
  Future<void> clearCache(String deviceIp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$deviceIp');
    } catch (_) {}
  }

  /// 清除所有设备的缓存
  Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  /// 对比缓存的文件列表与最新列表，返回是否需要更新
  ///
  /// 通过 `uniqueKey`（路径+大小+修改时间）做差集判断：
  /// - 任意一边的 key 集合不同 → 需要更新
  bool hasChanges(List<FileItem> cached, List<FileItem> latest) {
    if (cached.length != latest.length) return true;

    final cachedKeys = cached.map((f) => f.uniqueKey).toSet();
    final latestKeys = latest.map((f) => f.uniqueKey).toSet();

    return !cachedKeys.containsAll(latestKeys) ||
        !latestKeys.containsAll(cachedKeys);
  }

  // ---------------------------------------------------------------------------
  // JSON 序列化辅助
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _fileItemToJson(FileItem f) => {
        'name': f.name,
        'path': f.path,
        'size': f.size,
        'modifiedAt': f.modifiedAt?.millisecondsSinceEpoch,
        'isDirectory': f.isDirectory,
        'duration': f.duration,
      };

  FileItem _fileItemFromJson(Map<String, dynamic> json) => FileItem(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        size: json['size'] as int?,
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['modifiedAt'] as int)
            : null,
        isDirectory: json['isDirectory'] as bool? ?? false,
        duration: json['duration'] as int?,
      );
}
