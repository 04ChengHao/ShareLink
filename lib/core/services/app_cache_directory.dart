import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局文件缓存目录
///
/// 所有临时文件、视频缩略图、本地文件索引、ts 合并缓存、远程图片缓存
/// 统一存放于此目录，便于统一统计大小与清理。所有缓存类代码都应通过
/// 本类获取路径，避免各模块各自硬编码路径导致统计遗漏。
///
/// **与系统缓存统计一致**：
/// - 移动端（Android/iOS）基础目录使用系统缓存目录 [getTemporaryDirectory]
///   （Android 即 cacheDir），系统设置里「应用缓存」的统计才会把我们的缓存
///   计入，与应用内统计口径一致；缓存被系统/用户清理时视为正常语义，
///   下次启动自动全量重扫重建。
/// - 桌面端使用应用支持目录 [getApplicationSupportDirectory]（跨会话稳定，
///   不会被系统自动清理）。
///
/// **稳定性保证（跨启动复用）**：
/// - 首次解析成功后，把固定路径持久化到 SharedPreferences。之后每次启动
///   直接读回同一路径并复用（目录被删则按需重建），确保缓存只有一个、
///   可复用、可清理。
/// - 若上次固定的位置与当前平台首选位置不一致（如版本升级调整了基础
///   目录），会把旧目录内容整体迁移到新位置后再固定，缓存不丢失。
class AppCacheDirectory {
  AppCacheDirectory._();

  /// 缓存子目录名称（位于平台首选基础目录下）
  static const String dirName = 'share_link_cache';

  /// SharedPreferences 中用于固定缓存路径的键
  static const String _pinKey = 'share_link_app_cache_dir';

  /// 本次进程内已解析并固定的路径（避免重复解析）
  static String? _pinned;

  /// 获取全局缓存根目录
  static Future<Directory> get root async => Directory(await resolve());

  /// 当前进程已解析固定的缓存根路径（尚未解析时为 null）
  ///
  /// 供需要**同步**拿到缓存目录的场景使用（如列表卡片首帧同步探测
  /// 视频缩略图），避免异步等待造成的占位图闪烁。
  static String? get pinnedPath => _pinned;

  /// 获取全局缓存根目录路径字符串
  static Future<String> get path async => resolve();

  /// 解析并固定全局缓存路径
  ///
  /// 解析顺序：
  /// 1. 进程内已固定路径（最快）
  /// 2. SharedPreferences 里上次固定好的路径与当前平台首选一致 → 直接复用
  /// 3. 不一致（版本升级迁移）→ 旧目录内容整体搬到首选位置后固定
  /// 4. 无固定记录 → 解析首选位置并固定持久化
  static Future<String> resolve() async {
    if (_pinned != null && _ensureDir(_pinned!)) return _pinned!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final preferred = await _preferredDir();

      // 复用上次固定的路径：与首选位置一致时保证跨启动缓存不散落、可复用
      final saved = prefs.getString(_pinKey);
      if (saved != null && saved.isNotEmpty && _samePath(saved, preferred.path)) {
        _pinned = saved;
        return saved;
      }

      // 旧版本固定的位置与当前首选不一致：整体迁移（跨启动升级场景）
      if (saved != null && saved.isNotEmpty && Directory(saved).existsSync()) {
        await _migrateDirectory(Directory(saved), preferred);
      }

      // 固定路径并持久化，保证后续启动仍走同一目录
      await prefs.setString(_pinKey, preferred.path);
      _pinned = preferred.path;
      return preferred.path;
    } catch (e) {
      debugPrint('[AppCacheDirectory] 解析缓存目录失败: $e');
      // 最终兜底：当前临时目录下的子目录（本会话内可用，避免崩溃）
      final tmp = Directory(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$dirName',
      );
      if (!tmp.existsSync()) {
        await tmp.create(recursive: true);
      }
      _pinned = tmp.path;
      return tmp.path;
    }
  }

  /// 解析当前平台的首选缓存目录（`基础目录/share_link_cache`，自动创建）
  static Future<Directory> _preferredDir() async {
    String? base;
    try {
      base = (await _preferredBase()).path;
    } catch (e) {
      debugPrint('[AppCacheDirectory] 首选基础目录不可用: $e');
    }
    if (base == null) {
      try {
        base = (await getApplicationDocumentsDirectory()).path;
      } catch (e) {
        debugPrint('[AppCacheDirectory] 文档目录不可用: $e');
      }
    }
    if (base == null) {
      // 极端小概率情况才兜底临时目录，且一旦确定同样固定复用
      try {
        base = (await getTemporaryDirectory()).path;
      } catch (_) {}
    }
    if (base == null) {
      throw StateError('无法确定全局缓存目录');
    }

    final dir = Directory('$base${Platform.pathSeparator}$dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 当前平台首选的基础目录
  ///
  /// - 移动端：系统缓存目录（Android cacheDir / iOS 临时目录），
  ///   系统「应用缓存」统计才会计入，与应用内统计一致
  /// - 桌面端：应用支持目录（跨会话稳定）
  static Future<Directory> _preferredBase() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return getTemporaryDirectory();
    }
    return getApplicationSupportDirectory();
  }

  /// 比较两个路径是否指向同一位置（Windows 忽略大小写、统一分隔符）
  static bool _samePath(String a, String b) {
    var x = a.replaceAll('/', Platform.pathSeparator);
    var y = b.replaceAll('/', Platform.pathSeparator);
    if (!kIsWeb && Platform.isWindows) {
      x = x.toLowerCase();
      y = y.toLowerCase();
    }
    return x == y;
  }

  /// 把旧缓存目录整体迁移到新位置
  ///
  /// 优先目录改名（同卷零拷贝）；失败（跨卷/被占用）则递归复制后删除旧目录。
  static Future<void> _migrateDirectory(Directory from, Directory to) async {
    try {
      if (to.existsSync()) {
        await to.delete(recursive: true);
      }
      await from.rename(to.path);
      debugPrint('[AppCacheDirectory] 缓存目录已迁移: ${from.path} -> ${to.path}');
    } catch (e) {
      // 改名失败：逐项复制后删除旧目录
      try {
        if (!to.existsSync()) {
          await to.create(recursive: true);
        }
        await for (final entity
            in from.list(followLinks: false)) {
          final name = entity.uri.pathSegments.last;
          final target = '${to.path}${Platform.pathSeparator}$name';
          try {
            if (entity is Directory) {
              await _copyDir(entity, Directory(target));
            } else if (entity is File) {
              await entity.copy(target);
            }
          } catch (_) {}
        }
        await from.delete(recursive: true);
        debugPrint('[AppCacheDirectory] 缓存目录已复制迁移: ${from.path} -> ${to.path}');
      } catch (e2) {
        debugPrint('[AppCacheDirectory] 缓存目录迁移失败: $e2（旧目录保留，下次启动重试）');
      }
    }
  }

  /// 递归复制目录
  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final name = e.uri.pathSegments.last;
      final t = '${dst.path}${Platform.pathSeparator}$name';
      if (e is Directory) {
        await _copyDir(e, Directory(t));
      } else if (e is File) {
        await e.copy(t);
      }
    }
  }

  /// 确保目录存在且可用（不存在则创建），返回是否可用
  static bool _ensureDir(String path) {
    try {
      final d = Directory(path);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
      return d.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 清理历史版本散落的遗留缓存目录
  ///
  /// 1. 旧版本曾把缓存放在系统临时目录下的 `share_link_cache`（桌面端会话
  ///    间位置不稳定），统一目录启用后删除回收，避免越积越多。
  /// 2. 旧版本远程图片走 flutter_cache_manager 默认位置（系统临时目录下
  ///    `libCachedImageData`），统一到 [AppImageCacheManager] 后删除回收。
  /// 当前统一目录本身不受影响。
  static Future<void> cleanupLegacyLocations() async {
    if (kIsWeb) return;
    try {
      final current = _pinned ?? await resolve();
      final tmp = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;

      final legacy = Directory('${tmp.path}${sep}$dirName');
      if (legacy.absolute.path != Directory(current).absolute.path &&
          legacy.existsSync()) {
        await legacy.delete(recursive: true);
        debugPrint('[AppCacheDirectory] 已清理旧版遗留缓存目录: ${legacy.path}');
      }

      final legacyCn = Directory('${tmp.path}${sep}libCachedImageData');
      if (legacyCn.existsSync()) {
        await legacyCn.delete(recursive: true);
        debugPrint('[AppCacheDirectory] 已清理旧版远程图片缓存: ${legacyCn.path}');
      }
    } catch (e) {
      debugPrint('[AppCacheDirectory] 清理旧版遗留缓存目录失败: $e');
    }
  }
}
