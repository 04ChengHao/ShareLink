import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_cache_directory.dart';

/// 远程图片（CachedNetworkImage）统一磁盘缓存管理器
///
/// flutter_cache_manager 默认把图片缓存在系统临时目录下的 libCachedImageData，
/// 与全局缓存目录 [AppCacheDirectory] 相互分离，导致：
/// 1. 应用内缓存统计（递归统计全局缓存目录）遗漏远程图片，
///    与系统显示的应用缓存占用不一致；
/// 2. 设置页「清空缓存」清不掉远程图片缓存，越积越大。
///
/// 本管理器把图片文件统一放入全局缓存目录的 [dirName] 子目录，
/// 实现「统计 / 清理 / 复用」三处口径完全一致：
/// - 统计：getTempCacheSize 递归统计全局缓存目录，自然包含本目录
/// - 清理：设置页先调用 emptyCache() 清空索引与文件，再清空整个目录
/// - 复用：文件按 URL 键落盘，重启后直接命中，无需重新下载
///
/// 索引仓库使用平台默认实现（Android/iOS/macOS 为 sqflite，桌面为 JSON）。
/// 即使索引与文件出现不一致（如系统清理了缓存目录），CacheStore 会校验
/// 文件是否存在，失效条目自动重新下载，不会出现永久渲染失败。
class AppImageCacheManager {
  AppImageCacheManager._();

  /// 远程图片在全局缓存目录下的子目录名
  static const String dirName = 'remote_images';

  static CacheManager? _instance;

  /// 全局实例（供 CachedNetworkImage 的 cacheManager 参数使用）
  ///
  /// Web 平台没有本地文件系统，回退默认管理器（浏览器缓存）。
  static CacheManager get instance => _instance ??= _create();

  static CacheManager _create() {
    if (kIsWeb) return DefaultCacheManager();
    return CacheManager(
      Config(dirName, fileSystem: _AppCacheFileSystem()),
    );
  }
}

/// 把 flutter_cache_manager 的图片文件写入全局缓存目录 / remote_images
///
/// 注意：[FileSystem.createFile] 的 [File] 是 package:file 的类型
/// （flutter_cache_manager 的接口约定），不能用 dart:io 的 File 实现，
/// 否则类型不匹配（invalid_override）。
class _AppCacheFileSystem implements FileSystem {
  static const LocalFileSystem _fs = LocalFileSystem();

  @override
  Future<File> createFile(String name) async {
    final root = await AppCacheDirectory.resolve();
    final dir = _fs.directory(
      _fs.path.join(root, AppImageCacheManager.dirName),
    );
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    return dir.childFile(name);
  }
}
