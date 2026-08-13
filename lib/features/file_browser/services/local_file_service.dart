import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/services/app_cache_directory.dart';
import '../../../core/utils/platform_utils.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/file_category.dart';
import '../models/file_item.dart';

/// 文件访问服务接口
///
/// 定义文件扫描、分类、缓存和打开的标准接口。
/// 当前由 [LocalFileService] 实现本机文件访问，
/// 后续可由远程实现类完成局域网设备文件访问。
abstract class FileService {
  /// 扫描所有共享文件夹，返回完整文件列表
  Future<List<FileItem>> scanFiles(SharedContentSettings settings);

  /// 获取主文件列表（缓存）
  List<FileItem> get masterFileList;

  /// 根据分类筛选文件（使用缓存）
  List<FileItem> getFilesForCategory(FileCategory category);

  /// 检查文件是否有变更（与缓存对比）
  Future<bool> hasChanges(SharedContentSettings settings);

  /// 清除指定分类的缓存
  void clearCategoryCache(String categoryName);

  /// 清除所有缓存
  void clearAllCaches();

  /// 使用系统应用选择器打开文件
  Future<bool> openFile(String path);

  /// 生成视频缩略图，返回缩略图文件路径（失败返回 null）
  Future<String?> getVideoThumbnail(String videoPath);
}

/// 本机文件管理服务
///
/// 负责扫描共享文件夹、文件分类缓存、文件变更检测和系统打开。
/// 单例模式，确保全局缓存一致。
class LocalFileService implements FileService {
  LocalFileService._();
  static final LocalFileService instance = LocalFileService._();

  // 主文件列表缓存
  List<FileItem> _masterFileList = [];

  // 主文件列表唯一 key 集合，用于变更检测
  Set<String> _masterFileKeys = {};

  // 分类缓存：categoryName -> filtered file list
  final Map<String, List<FileItem>> _categoryCache = {};

  // 视频缩略图缓存：videoPath -> thumbnailPath（null 表示生成失败）
  final Map<String, String?> _thumbnailCache = {};

  @override
  List<FileItem> get masterFileList => List.unmodifiable(_masterFileList);

  /// 根据共享内容设置获取需要扫描的目录路径列表
  List<String> _getScanPaths(SharedContentSettings settings) {
    final paths = <String>[];

    if (kIsWeb) return paths;

    if (Platform.isAndroid) {
      if (settings.album) {
        paths.add('/storage/emulated/0/DCIM');
        paths.add('/storage/emulated/0/Pictures');
        paths.add('/storage/emulated/0/Movies');
      }
      if (settings.music) {
        paths.add('/storage/emulated/0/Music');
      }
      if (settings.documents) {
        paths.add('/storage/emulated/0/Documents');
      }
      if (settings.downloads) {
        paths.add('/storage/emulated/0/Download');
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (settings.album) {
        paths.add('$userProfile\\Pictures');
      }
      if (settings.music) {
        paths.add('$userProfile\\Music');
      }
      if (settings.documents) {
        paths.add('$userProfile\\Documents');
      }
      if (settings.downloads) {
        paths.add('$userProfile\\Downloads');
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      if (settings.album) {
        paths.add('$home/Pictures');
      }
      if (settings.music) {
        paths.add('$home/Music');
      }
      if (settings.documents) {
        paths.add('$home/Documents');
      }
      if (settings.downloads) {
        paths.add('$home/Downloads');
      }
    }

    // 自定义共享文件夹
    if (settings.folderEnabled) {
      paths.addAll(settings.folders);
    }

    return paths;
  }

  /// 获取共享根目录路径列表（用于远程文件访问安全校验）
  List<String> getSharedRoots(SharedContentSettings settings) {
    return _getScanPaths(settings);
  }

  /// 递归扫描单个目录（手动递归，单个子目录失败不影响其他目录）
  ///
  /// 不使用 list(recursive: true)，因为遇到无权限的子目录时整个流会中断，
  /// 导致后续可访问的文件全部丢失。手动递归可以为每个子目录单独 try/catch。
  Future<int> _scanDirectory(String dirPath, List<FileItem> output) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return 0;
    }

    int count = 0;
    List<FileSystemEntity> entities;
    try {
      // 非递归列出当前目录的直接子项
      entities = dir.listSync(followLinks: false);
    } catch (_) {
      return 0;
    }

    for (final entity in entities) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          output.add(FileItem(
            name: entity.uri.pathSegments.last,
            path: entity.path,
            size: stat.size,
            modifiedAt: stat.modified,
            isDirectory: false,
          ));
          count++;
        } catch (_) {
          // 跳过无法读取的文件
        }
      } else if (entity is Directory) {
        // 手动递归子目录，单个失败不影响整体
        try {
          count += await _scanDirectory(entity.path, output);
        } catch (_) {
          // 跳过子目录
        }
      } else if (entity is Link) {
        // Android FUSE 文件系统下某些文件以链接形式存在
        try {
          final target = await entity.target();
          final targetType =
              await FileSystemEntity.type(target, followLinks: true);
          if (targetType == FileSystemEntityType.file) {
            final file = File(target);
            final stat = await file.stat();
            output.add(FileItem(
              name: entity.uri.pathSegments.last,
              path: entity.path,
              size: stat.size,
              modifiedAt: stat.modified,
              isDirectory: false,
            ));
            count++;
          } else if (targetType == FileSystemEntityType.directory) {
            count += await _scanDirectory(target, output);
          }
        } catch (_) {
          // 跳过链接
        }
      }
    }

    return count;
  }

  @override
  Future<List<FileItem>> scanFiles(SharedContentSettings settings) async {
    if (kIsWeb) return [];

    final paths = _getScanPaths(settings);

    final files = <FileItem>[];

    // 并行扫描所有目录
    await Future.wait(paths.map((p) => _scanDirectory(p, files)));

    // 更新主列表和 key 集合
    _masterFileList = files;
    _masterFileKeys = files.map((f) => f.uniqueKey).toSet();

    // 清除分类缓存（主列表已更新）
    _categoryCache.clear();

    return files;
  }

  @override
  List<FileItem> getFilesForCategory(FileCategory category) {
    if (_categoryCache.containsKey(category.name)) {
      return _categoryCache[category.name]!;
    }

    final filtered = _masterFileList.where((f) => category.matches(f)).toList();
    _categoryCache[category.name] = filtered;
    return filtered;
  }

  @override
  Future<bool> hasChanges(SharedContentSettings settings) async {
    if (kIsWeb) return false;

    final paths = _getScanPaths(settings);
    final currentKeys = <String>{};

    for (final path in paths) {
      await _collectFileKeys(path, currentKeys);
    }

    if (currentKeys.length != _masterFileKeys.length) return true;
    return !currentKeys.containsAll(_masterFileKeys);
  }

  /// 手动递归收集文件 key（与 _scanDirectory 同样的容错策略）
  Future<void> _collectFileKeys(String dirPath, Set<String> keys) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }

    for (final entity in entities) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          final key = '${entity.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
          keys.add(key);
        } catch (_) {
          // 跳过
        }
      } else if (entity is Directory) {
        try {
          await _collectFileKeys(entity.path, keys);
        } catch (_) {
          // 跳过子目录
        }
      }
    }
  }

  @override
  void clearCategoryCache(String categoryName) {
    _categoryCache.remove(categoryName);
  }

  @override
  void clearAllCaches() {
    _categoryCache.clear();
  }

  /// 文件扩展名到 MIME 类型映射
  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mkv': 'video/x-matroska',
    'avi': 'video/x-msvideo',
    'mov': 'video/quicktime',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    'rmvb': 'application/vnd.rn-realmedia-vbr',
    'ts': 'video/mp2t',
    '3gp': 'video/3gpp',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'flac': 'audio/flac',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
    'wma': 'audio/x-ms-wma',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'log': 'text/plain',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed',
    'apk': 'application/vnd.android.package-archive',
    'dart': 'text/x-dart',
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    'java': 'text/x-java-source',
    'py': 'text/x-python',
    'c': 'text/x-csrc',
    'cpp': 'text/x-c++src',
  };

  /// 获取文件扩展名对应的 MIME 类型
  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _mimeTypes[ext] ?? '*/*';
  }

  @override
  Future<bool> openFile(String path) async {
    if (kIsWeb) return false;

    final mimeType = _getMimeType(path);

    // Android：使用 MethodChannel 调用系统选择器
    if (PlatformUtils.isMobile && !kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.sharelink.app/file');
        await channel.invokeMethod('openFileWithChooser', {
          'path': path,
          'mimeType': mimeType,
        });
        return true;
      } on PlatformException {
        return false;
      }
    }

    // 桌面端：使用 open_filex 打开
    try {
      final result = await OpenFilex.open(path, type: mimeType);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getVideoThumbnail(String videoPath) async {
    if (kIsWeb) return null;

    // 检查缓存
    if (_thumbnailCache.containsKey(videoPath)) {
      return _thumbnailCache[videoPath];
    }

    String? result;

    try {
      final cacheDir = await AppCacheDirectory.root;
      final thumbPath =
          '${cacheDir.path}${Platform.pathSeparator}thumb_${videoPath.hashCode}.jpg';

      // 如果缩略图已存在则直接返回
      if (File(thumbPath).existsSync()) {
        result = thumbPath;
      } else {
        // 使用 fc_native_video_thumbnail 插件（原生 API，全平台支持）
        final plugin = FcNativeVideoThumbnail();
        final generated = await plugin.saveThumbnailToFile(
          srcFile: videoPath,
          destFile: thumbPath,
          width: 256,
          height: 256,
          quality: 75,
        );
        if (generated && File(thumbPath).existsSync()) {
          result = thumbPath;
        }
      }
    } catch (e) {
      debugPrint('生成视频缩略图失败: $e');
    }

    _thumbnailCache[videoPath] = result;
    return result;
  }
}
