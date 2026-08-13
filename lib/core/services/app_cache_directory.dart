import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 全局文件缓存目录
///
/// 所有临时文件、视频缩略图、远程下载缓存统一存放于此目录，
/// 便于统一统计大小与清理。所有缓存类代码都应通过本类获取路径，
/// 避免各模块各自硬编码路径导致统计遗漏。
class AppCacheDirectory {
  AppCacheDirectory._();

  /// 缓存子目录名称（位于系统应用缓存目录下）
  static const String dirName = 'share_link_cache';

  /// 获取全局缓存根目录
  static Future<Directory> get root async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取全局缓存根目录路径字符串
  static Future<String> get path async => (await root).path;
}