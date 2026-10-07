import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_metadata/media_metadata.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/services/app_cache_directory.dart';
import '../../../core/utils/platform_utils.dart';
import 'media_duration_service.dart';
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

/// 扫描时从磁盘找到的一个文件（仅 stat，不做内容处理）
class _FoundFile {
  final String name;
  final String path;
  final int size;
  final DateTime modified;
  const _FoundFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });
}

/// 本机文件管理服务
///
/// 负责扫描共享文件夹、文件分类缓存、文件变更检测和系统打开。
/// 单例模式，确保全局缓存一致。
class LocalFileService implements FileService {
  LocalFileService._();
  static final LocalFileService instance = LocalFileService._();

  // 进程内文件缓存：path -> FileItem（含 size/modifiedAt/duration）
  //
  // key 用文件路径，配合 size+modifiedAt 判断文件是否变化：
  // - 未变化的文件直接复用（跳过缩略图/图片解码/视频校验/时长等重处理）
  // - 已变化/新增的文件才重建并做内容校验
  // 这是"刷新只扫当前分类 + 缓存复用"的核心，避免每次刷新全量重处理。
  final Map<String, FileItem> _pathCache = {};

  // 已通过可用性校验（非损坏）的文件路径集合
  final Set<String> _verified = {};

  // 分类缓存：categoryName -> filtered file list
  final Map<String, List<FileItem>> _categoryCache = {};

  // 渐进扫描代数：每次启动新的渐进扫描自增。
  // 切换分类/设备会启动新一轮 scanFilesProgressive，而本服务是共享单例，
  // 若旧扫描不中止就会与新一轮并发改写 _pathCache/_verified/_categoryCache，
  // 造成列表错乱（残留数据互相污染、文件忽显忽隐）。
  // 每轮扫描在每次让出/批量操作前检查代数，已被取代则立即放弃。
  int _scanEpoch = 0;

  // 视频缩略图缓存：videoPath -> thumbnailPath（null 表示生成失败）
  final Map<String, String?> _thumbnailCache = {};

  // ts 合并校验失败负缓存：dirPath -> '总大小|最大mtime' 签名。
  // 同签名目录跳过重复的「全量拼接 + 真实起播探测」，避免每次启动都把
  // 不可播放的分片写成大文件再删掉（加密 HLS 目录会反复产生 GB 级写入）。
  // 碎片变化后签名不符自动重试。随磁盘索引持久化。
  final Map<String, String> _rejectedTs = {};

  // 磁盘持久化状态：是否已从磁盘加载过本地文件索引
  bool _loaded = false;
  Future<void>? _loadFuture;

  // 本地文件索引磁盘文件名（位于 AppCacheDirectory 内，无需单独统计大小）
  static const String indexFileName = 'local_index.json';
  static const String _indexFileName = indexFileName;

  @override
  List<FileItem> get masterFileList =>
      List.unmodifiable(_pathCache.values.toList());

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

  /// 最近一次成功扫描的共享设置签名（用于快速判断缓存是否仍新鲜）
  String _scanSig = '';

  /// 由共享设置生成轻量签名（仅比较开关与路径，不遍历文件）
  String _buildScanSig(SharedContentSettings s) {
    final folders = [...s.folders]..sort();
    return '${s.album}|${s.music}|${s.documents}|${s.downloads}|'
        '${s.folderEnabled}|${folders.join(',')}';
  }

  /// 缓存是否可直接复用（共享设置未变化且有已扫描数据）
  ///
  /// 相比 [hasChanges] 免去整树遍历，切换设备/标签时开销极低。
  bool isCacheFresh(SharedContentSettings settings) =>
      _pathCache.isNotEmpty && _scanSig == _buildScanSig(settings);

  /// 分类是否已有可用的缓存数据（避免每次切换分类都重扫）
  bool isCategoryDataReady(FileCategory category) {
    if (!isCacheFresh(_lastSettings)) return false;
    if (category.selectAll) return _pathCache.isNotEmpty;
    return _pathCache.values.any((f) => category.matches(f));
  }

  /// 最近一次扫描所用设置（供 [isCategoryDataReady] 使用）
  SharedContentSettings _lastSettings = const SharedContentSettings();

  @override
  Future<List<FileItem>> scanFiles(
    SharedContentSettings settings, {
    FileCategory? category,
    bool force = false,
  }) async {
    if (kIsWeb) return [];
    _lastSettings = settings;
    await _ensureLoaded();

    final paths = _getScanPaths(settings);

    // 分类限定的扩展名过滤；null 表示扫描所有类型（如分享全量列表）
    final extFilter = (category == null || category.selectAll)
        ? null
        : category.fileTypes.map((e) => e.toLowerCase()).toSet();

    // 仅收集当前扫描范围内的文件（cheap：只 stat，不做内容重处理）
    // 目录遍历 + stat 在后台 Isolate 中执行，不阻塞 UI 渲染线程
    final found = await _collectFiles(paths, extFilter: extFilter);

    // 增量：未变化 → 复用缓存；新增/变化 → 重建并做可用性校验（图片解码/视频校验）
    // 注意：时间用毫秒比较。磁盘索引以毫秒持久化，而 stat 带微秒精度，
    // 直接 DateTime == 比较在重启后必然失败，导致每次启动全量重校验。
    for (final entry in found.values) {
      // ts 碎片不单独入缓存渲染，统一走「合并 → 校验 → 渲染」流程
      if (_extOf(entry.path) == 'ts') continue;
      final prev = _pathCache[entry.path];
      final unchanged = !force &&
          prev != null &&
          prev.size == entry.size &&
          prev.modifiedAt?.millisecondsSinceEpoch ==
              entry.modified.millisecondsSinceEpoch &&
          _verified.contains(entry.path);
      if (unchanged) {
        // 直接复用缓存：跳过缩略图/图片解码/视频校验/时长读取
        continue;
      }

      final item = FileItem(
        name: entry.name,
        path: entry.path,
        size: entry.size,
        modifiedAt: entry.modified,
      );
      if (await _isUsable(item)) {
        _pathCache[entry.path] = item;
        _verified.add(entry.path);
      } else {
        // 损坏/不可用 → 从缓存剔除
        _pathCache.remove(entry.path);
        _verified.remove(entry.path);
      }
    }

    // 删除检测：扫描范围内缓存存在但磁盘上已不见的文件 → 移除并联动清理派生缓存
    await _pruneRemoved(found, extFilter);

    // ts 分片仅在视频分类（或全量扫描）下合并：先合并 → 校验可播放 → 再入缓存
    if (extFilter == null || extFilter.contains('ts')) {
      await _mergeTsFromFound(found);
    }

    _scanSig = _buildScanSig(settings);

    // 主列表已变化，清除分类级联缓存，避免返回过期数据
    _categoryCache.clear();

    await _persistCache();

    return masterFileList;
  }

  /// 渐进式扫描（本机）：快速返回 + 后台分批校验，渲染与扫描并行。
  ///
  /// 1. 快速收集文件（仅 stat）+ 复用未变化缓存，先把新文件纳入列表**立即返回**，
  ///    让 UI 马上渲染，不再被“图片解码/视频校验”等重处理阻塞在 loading；
  /// 2. 后台分批校验新增/变更文件的可用性（图片解码/视频校验），每批 `await` 让出
  ///    事件循环一瞬，保证界面不卡顿；损坏文件在校验中被逐批剔除。
  ///
  /// [onProgress] 每批校验完成（或首屏就绪）时回调 `(已校验数, 总数, 当前主列表)`，
  /// 调用方可借此渐进刷新列表。最终仍返回完整列表供 await 使用。
  Future<List<FileItem>> scanFilesProgressive(
    SharedContentSettings settings, {
    FileCategory? category,
    bool force = false,
    void Function(int done, int total, List<FileItem> partial)? onProgress,
  }) async {
    if (kIsWeb) return [];
    // 本轮扫描代数：启动即自增，取代可能仍在前一分类/设备进行中的旧扫描
    final epoch = ++_scanEpoch;
    _lastSettings = settings;
    await _ensureLoaded();
    if (epoch != _scanEpoch) return masterFileList;

    final paths = _getScanPaths(settings);
    final extFilter = (category == null || category.selectAll)
        ? null
        : category.fileTypes.map((e) => e.toLowerCase()).toSet();

    // 收集本次扫描范围内的文件（后台 Isolate，不阻塞 UI）
    final found = await _collectFiles(paths, extFilter: extFilter);
    if (epoch != _scanEpoch) return masterFileList;

    // 需要后台校验的新增/变更文件；先把它们快速纳入缓存，立即显示。
    // ts 碎片除外：必须等「合并 → 校验可播放」通过后才渲染，
    // 避免先渲染碎片再合并刷新列表的闪烁。
    final toValidate = <String>[];
    for (final entry in found.values) {
      if (_extOf(entry.path) == 'ts') continue;
      final prev = _pathCache[entry.path];
      final unchanged = !force &&
          prev != null &&
          prev.size == entry.size &&
          prev.modifiedAt?.millisecondsSinceEpoch ==
              entry.modified.millisecondsSinceEpoch &&
          _verified.contains(entry.path);
      if (unchanged) continue;
      toValidate.add(entry.path);
      _pathCache[entry.path] = FileItem(
        name: entry.name,
        path: entry.path,
        size: entry.size,
        modifiedAt: entry.modified,
      );
    }

    // 删除检测
    await _pruneRemoved(found, extFilter);
    if (epoch != _scanEpoch) return masterFileList;

    _scanSig = _buildScanSig(settings);
    _categoryCache.clear();

    final total = toValidate.length;
    // 首屏即可渲染
    if (onProgress != null) {
      onProgress(0, total, masterFileList);
    }

    // 后台分批校验（每批让出一帧，避免阻塞 UI）
    const batch = 30;
    var lastEmit = DateTime.now();
    for (var i = 0; i < total; i += batch) {
      final end = (i + batch) > total ? total : (i + batch);
      for (var j = i; j < end; j++) {
        final path = toValidate[j];
        final item = _pathCache[path];
        if (item == null) continue;
        if (await _isUsable(item)) {
          _verified.add(path);
        } else {
          // 损坏/不可用 → 剔除
          _pathCache.remove(path);
          _verified.remove(path);
        }
      }
      // 让出主线程渲染一帧
      await Future.delayed(const Duration(milliseconds: 1));
      // 已被新扫描取代（切换分类/设备）：立即放弃，不再改写共享缓存
      if (epoch != _scanEpoch) return masterFileList;
      if (onProgress != null) {
        final now = DateTime.now();
        // 100ms 节流：每次回调都会触发全量列表重建与分组重算，
        // 过高频（如 40ms）会在大列表下造成持续掉帧
        if (now.difference(lastEmit).inMilliseconds >= 100) {
          lastEmit = now;
          onProgress(end, total, masterFileList);
        }
      }
    }

    // ts 碎片合并：先合并 → 校验可播放 → 校验通过才入缓存渲染（损坏的剔除）
    if (extFilter == null || extFilter.contains('ts')) {
      await _mergeTsFromFound(found);
    }
    // 合并期间可能已被新扫描取代：避免旧扫描的结果覆盖新扫描
    if (epoch != _scanEpoch) return masterFileList;
    if (onProgress != null) {
      onProgress(total, total, masterFileList);
    }

    await _persistCache();

    return masterFileList;
  }

  /// 在后台 Isolate 中递归收集扫描路径下的全部文件（纯 dart:io，同步 stat）
  ///
  /// 大目录遍历（上万文件的 listSync + stat）如果在主 Isolate 执行会
  /// 阻塞 UI 线程造成掉帧；放到独立 Isolate 后文件扫描与界面渲染互不干扰。
  /// （调用方均已通过 kIsWeb 守卫，仅原生平台可达）
  static Future<Map<String, _FoundFile>> _collectFiles(
    List<String> paths, {
    Set<String>? extFilter,
  }) {
    return Isolate.run(() => _collectAllSync(paths, extFilter));
  }

  /// 后台 Isolate 执行的同步收集（返回纯数据，可跨 Isolate 传输）
  static Map<String, _FoundFile> _collectAllSync(
    List<String> paths,
    Set<String>? extFilter,
  ) {
    final found = <String, _FoundFile>{};
    for (final p in paths) {
      _collectDirSync(p, found, extFilter);
    }
    return found;
  }

  /// 同步递归收集单个目录（仅在后台 Isolate 中执行，同步 IO 不影响 UI）
  static void _collectDirSync(
    String dirPath,
    Map<String, _FoundFile> found,
    Set<String>? extFilter,
  ) {
    List<FileSystemEntity> entities;
    try {
      entities = Directory(dirPath).listSync(followLinks: false);
    } catch (_) {
      return;
    }

    for (final entity in entities) {
      // 跳过隐藏文件/文件夹（如 .thumbnails、.nomedia、.trash 等，文件管理器里不可见）
      if (entity.uri.pathSegments.last.startsWith('.')) continue;
      if (entity is File) {
        try {
          final stat = entity.statSync();
          // 分类限定：只收集匹配当前分类扩展名的文件
          if (extFilter != null && !extFilter.contains(_extOf(entity.path))) {
            continue;
          }
          found[entity.path] = _FoundFile(
            name: entity.uri.pathSegments.last,
            path: entity.path,
            size: stat.size,
            modified: stat.modified,
          );
        } catch (_) {
          // 跳过无法 stat 的文件
        }
      } else if (entity is Directory) {
        _collectDirSync(entity.path, found, extFilter);
      } else if (entity is Link) {
        try {
          final target = entity.targetSync();
          final type = FileSystemEntity.typeSync(target, followLinks: true);
          if (type == FileSystemEntityType.file) {
            final stat = File(target).statSync();
            if (extFilter != null && !extFilter.contains(_extOf(entity.path))) {
              continue;
            }
            found[entity.path] = _FoundFile(
              name: entity.uri.pathSegments.last,
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            );
          } else if (type == FileSystemEntityType.directory) {
            _collectDirSync(target, found, extFilter);
          }
        } catch (_) {
          // 跳过链接
        }
      }
    }
  }

  /// 删除检测 + 派生缓存联动清理
  ///
  /// 把缓存中"属于当前扫描范围但磁盘上已不存在"的文件移除，并同步清理：
  /// - 视频缩略图磁盘文件（按确定性命名 thumb_路径哈希.jpg 直查，
  ///   应用重启后内存映射为空时依然能清理）
  /// - 媒体时长缓存（按 文件名|大小 后缀匹配，覆盖所有设备来源的记录）
  ///
  /// 合并 ts 项不在此处理（由 [_mergeTsFromFound] 管理其失效与清理）。
  Future<void> _pruneRemoved(
    Map<String, _FoundFile> found,
    Set<String>? extFilter,
  ) async {
    if (_pathCache.isEmpty) return;
    final seen = found.keys.toSet();
    final toRemove = <String>[];
    for (final path in _pathCache.keys) {
      final item = _pathCache[path]!;
      if (item.isMergedTs) continue; // 合并项由合并流程管理
      final inScope =
          extFilter == null || extFilter.contains(item.extension);
      if (inScope && !seen.contains(path)) {
        toRemove.add(path);
      }
    }
    if (toRemove.isEmpty) return;

    final cacheRoot = (await AppCacheDirectory.root).path;
    final sep = Platform.pathSeparator;
    for (final path in toRemove) {
      final item = _pathCache.remove(path);
      _verified.remove(path);
      if (item == null) continue;
      // 缩略图：内存映射 + 磁盘文件（确定性命名，重启后也能清理）
      final memThumb = _thumbnailCache.remove(path);
      final thumbPath = memThumb ?? '$cacheRoot${sep}thumb_${path.hashCode}.jpg';
      try {
        final f = File(thumbPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      // 时长缓存
      MediaDurationService.instance.removeDurationsForFile(item.name, item.size);
    }
    debugPrint('[Scan] 删除已移除文件 ${toRemove.length} 个');
  }

  static String _extOf(String path) {
    final index = path.lastIndexOf('.');
    if (index <= 0 || index == path.length - 1) return '';
    return path.substring(index + 1).toLowerCase();
  }

  /// 合并本次扫描到的 ts 碎片：**先合并 → 校验可播放 → 通过才入缓存渲染**。
  ///
  /// 与旧流程（先渲染碎片，再整理成一个文件后刷新列表）不同：
  /// - 碎片不进入列表/缓存，列表中只出现校验通过的合并视频项；
  /// - 合并项校验失败（拼接失败 / 读不到时长）时剔除并清理临时文件；
  /// - 碎片未变化的目录直接复用已校验的合并项（快速路径）；
  /// - 目录碎片数不足 2 个的合并项视为失效并清理。
  ///
  /// [found] 为本次扫描收集到的全部文件（含 ts 碎片）。
  Future<void> _mergeTsFromFound(Map<String, _FoundFile> found) async {
    // 按目录分组收集碎片
    final byDir = <String, List<_FoundFile>>{};
    for (final f in found.values) {
      if (_extOf(f.path) != 'ts') continue;
      byDir.putIfAbsent(File(f.path).parent.path, () => []).add(f);
    }
    if (byDir.isEmpty) return;

    // 清理失效合并项：目录已不存在 / 碎片数不足 2 个
    for (final e in _pathCache.values.toList()) {
      if (!e.isMergedTs) continue;
      final frags = byDir[e.path];
      if (frags == null || frags.length < 2) {
        _removeMergedTs(e.path);
      }
    }

    // 同步清理失效的失败签名（目录已不存在 / 碎片数不足 2 个）
    _rejectedTs.removeWhere(
      (p, _) => !byDir.containsKey(p) || byDir[p]!.length < 2,
    );

    for (final entry in byDir.entries) {
      final dirPath = entry.key;
      final frags = entry.value;

      if (frags.length < 2) {
        // 单个碎片：按普通文件处理（未变化复用，变化则重建校验）
        final f = frags.first;
        final prev = _pathCache[f.path];
        final unchanged = prev != null &&
            prev.size == f.size &&
            prev.modifiedAt?.millisecondsSinceEpoch ==
                f.modified.millisecondsSinceEpoch &&
            _verified.contains(f.path);
        if (unchanged) continue;
        final item = FileItem(
          name: f.name,
          path: f.path,
          size: f.size,
          modifiedAt: f.modified,
        );
        if (await _isUsable(item)) {
          _pathCache[f.path] = item;
          _verified.add(f.path);
        } else {
          _pathCache.remove(f.path);
          _verified.remove(f.path);
        }
        continue;
      }

      // 多碎片：清除可能残留的碎片独立缓存项，列表只保留合并项
      for (final f in frags) {
        _pathCache.remove(f.path);
        _verified.remove(f.path);
      }

      final sorted = List<_FoundFile>.from(frags)
        ..sort((a, b) => _naturalCompare(a.name, b.name));
      final want = sorted.fold<int>(0, (s, f) => s + f.size);
      var maxModMs = 0;
      for (final f in sorted) {
        final ms = f.modified.millisecondsSinceEpoch;
        if (ms > maxModMs) maxModMs = ms;
      }

      // 快速路径：碎片未变化且合并项已校验 → 直接复用
      final prev = _pathCache[dirPath];
      if (prev != null &&
          prev.isMergedTs &&
          _verified.contains(dirPath) &&
          prev.size == want &&
          (prev.modifiedAt?.millisecondsSinceEpoch ?? -1) == maxModMs) {
        continue;
      }

      // 负缓存快速路径：同签名目录此前已判定不可播放 → 跳过重复校验
      if (_rejectedTs[dirPath] == '$want|$maxModMs') {
        continue;
      }

      final dirName = File(dirPath).uri.pathSegments.last.isEmpty
          ? 'video'
          : File(dirPath).uri.pathSegments.last;
      final item = FileItem(
        name: '$dirName.ts',
        path: dirPath,
        isDirectory: false,
        size: want,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(maxModMs),
        tsFragments: sorted.map((f) => f.path).toList(),
      );
      if (await _validateMergedTs(item)) {
        _pathCache[dirPath] = item;
        _verified.add(dirPath);
        _rejectedTs.remove(dirPath);
      } else {
        _removeMergedTs(dirPath);
        // 记录失败签名：碎片未变化时下次扫描直接跳过，不再反复拼接探测
        _rejectedTs[dirPath] = '$want|$maxModMs';
      }
    }
  }

  /// 移除 ts 合并项并清理其派生缓存（合并临时文件、缩略图、时长）
  void _removeMergedTs(String dirPath) {
    final item = _pathCache.remove(dirPath);
    _verified.remove(dirPath);
    _thumbnailCache.remove(dirPath);
    if (item != null) {
      MediaDurationService.instance.removeDurationsForFile(item.name, item.size);
    }
    AppCacheDirectory.root.then((dir) {
      for (final name in [
        'ts_merged_${dirPath.hashCode}.ts',
        'thumb_${dirPath.hashCode}.jpg',
      ]) {
        try {
          final f = File('${dir.path}${Platform.pathSeparator}$name');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    });
  }

  /// ts 合并项可加载性校验：拼接分片为临时文件后验证其**真的能播放**
  ///
  /// 校验分两层：
  /// 1. 结构校验：MPEG-TS 包以 188 字节为一个包、每包首字节为同步字节 0x47，
  ///    检查文件头第 0/188/376 字节。非 TS 内容（如把 TypeScript 源码等
  ///    同扩展名文件误合并）会在此层被拒绝。
  /// 2. 播放校验：用 media_kit 真实起播（静音），等待播放位置前进；
  ///    位置不动或报错即判定损坏（如加密的 HLS 分片拼接后能读到时长
  ///    但根本无法解码播放）。仅探测时长不足以判定可播放。
  ///
  /// - 已存在同尺寸的完整合并文件 → 之前已通过校验，直接视为可用（快速路径）
  /// - 校验失败 → 删除临时合并文件并返回 false，调用方会把该项从列表剔除
  Future<bool> _validateMergedTs(FileItem item) async {
    if (!item.isMergedTs ||
        item.tsFragments == null ||
        item.tsFragments!.isEmpty) {
      return false;
    }
    try {
      final cacheDir = await AppCacheDirectory.root;
      final mergedPath =
          '${cacheDir.path}${Platform.pathSeparator}ts_merged_${item.path.hashCode}.ts';
      final want = item.size ?? 0;
      // 快速路径：完整合并文件已存在 → 之前已通过「结构 + 播放」双层校验
      if (want > 0 &&
          File(mergedPath).existsSync() &&
          File(mergedPath).lengthSync() == want) {
        return true;
      }
      // 首次生成：拼接后做结构 + 播放双层校验
      final written = await _writeMergedTs(item, mergedPath);
      if (!written) return false;
      final f = File(mergedPath);
      if (!f.existsSync() || f.lengthSync() <= 0) return false;
      if (!_hasTsSyncBytes(f)) {
        try {
          await f.delete();
        } catch (_) {}
        return false;
      }
      if (!await _isPlayableMedia(f.path)) {
        try {
          await f.delete();
        } catch (_) {}
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// MPEG-TS 结构校验：检查文件头部 0/188/376 字节处是否为同步字节 0x47
  ///
  /// TS 流每个包固定 188 字节且以 0x47 开头；非 TS 内容（文本、加密裸数据、
  /// 随机数据）几乎不可能同时命中三个位置的同步字节。
  bool _hasTsSyncBytes(File f) {
    try {
      final head = f.openSync();
      try {
        final buf = List<int>.filled(377, 0);
        final read = head.readIntoSync(buf, 0, 377);
        if (read < 377) return false;
        return buf[0] == 0x47 && buf[188] == 0x47 && buf[376] == 0x47;
      } finally {
        head.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// 真实播放探测：media_kit 静音起播，播放位置能前进才算可播放
  ///
  /// 仅能读到容器时长不代表可播放（加密 HLS 分片拼接即如此）。
  /// 位置前进说明解复用 + 解码时钟已正常运转。
  Future<bool> _isPlayableMedia(String path) async {
    if (kIsWeb) return true;
    final player = Player();
    String? error;
    var maxPosMs = 0;
    final subs = <StreamSubscription<dynamic>>[
      player.stream.error.listen((e) {
        if (e.isNotEmpty) error ??= e;
      }),
      player.stream.position.listen((p) {
        if (p.inMilliseconds > maxPosMs) maxPosMs = p.inMilliseconds;
      }),
    ];
    try {
      // 静音播放，避免校验期间外放声音
      await player.setVolume(0);
      await player
          .open(Media(Uri.file(path).toString()), play: true)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      // 等待：报错 → 不可播放；位置前进 ≥300ms → 可播放；超时看位置
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(deadline)) {
        if (error != null) return false;
        if (maxPosMs >= 300) return true;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return error == null && maxPosMs > 0;
    } catch (_) {
      return false;
    } finally {
      for (final s in subs) {
        try {
          await s.cancel();
        } catch (_) {}
      }
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  /// 将 ts 分片按顺序拼接写入 [mergedPath]，任一碎片缺失/读取失败即返回 false
  Future<bool> _writeMergedTs(FileItem item, String mergedPath) async {
    IOSink? sink;
    var ok = true;
    try {
      sink = File(mergedPath).openWrite();
      for (final frag in item.tsFragments!) {
        if (!File(frag).existsSync()) {
          ok = false;
          break;
        }
        await sink.addStream(File(frag).openRead());
      }
    } catch (e) {
      debugPrint('[TsMerge] 拼接分片失败: $e');
      ok = false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
    }
    if (!ok) {
      try {
        final f = File(mergedPath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    return ok;
  }

  /// 自然排序比较（数字段按数值比较，避免 2.ts 排在 10.ts 之后）
  int _naturalCompare(String a, String b) {
    final ra = RegExp(r'(\d+)|(\D+)').allMatches(a).map((m) => m.group(0)!).toList();
    final rb = RegExp(r'(\d+)|(\D+)').allMatches(b).map((m) => m.group(0)!).toList();
    final n = ra.length < rb.length ? ra.length : rb.length;
    for (var i = 0; i < n; i++) {
      final x = ra[i];
      final y = rb[i];
      final xn = int.tryParse(x);
      final yn = int.tryParse(y);
      if (xn != null && yn != null) {
        if (xn != yn) return xn.compareTo(yn);
      } else {
        final c = x.toLowerCase().compareTo(y.toLowerCase());
        if (c != 0) return c;
      }
    }
    return ra.length.compareTo(rb.length);
  }

  /// 返回可供播放的本地路径
  ///
  /// 普通文件返回自身；ts 合并项会把各分片按顺序拼成一个缓存 .ts 后返回。
  /// 拼接失败（碎片缺失/读取失败）返回 null，调用方应提示错误，
  /// 不能把残缺文件交给播放器。
  Future<String?> resolvePlayablePath(FileItem item) async {
    if (!item.isMergedTs) return item.path;
    final cacheDir = await AppCacheDirectory.root;
    final mergedPath =
        '${cacheDir.path}${Platform.pathSeparator}ts_merged_${item.path.hashCode}.ts';
    final want = item.size ?? 0;
    if (File(mergedPath).existsSync() && File(mergedPath).lengthSync() == want && want > 0) {
      return mergedPath;
    }
    final ok = await _writeMergedTs(item, mergedPath);
    return ok ? mergedPath : null;
  }

  /// 单文件可用性判断（仅对新增/变更文件调用）
  ///
  /// - 空文件（size<=0）直接移除
  /// - 图片尝试实际解码，解码失败（损坏、伪装成图片）则移除
  /// - 视频用原生容器读取做损坏校验（#4），仅对可靠可解析的封装判定，
  ///   避免误删合法但未支持的 .ts/.rmvb 等
  /// - 目录、ts 合并项（path 为目录）跳过校验
  Future<bool> _isUsable(FileItem f) async {
    try {
      if (f.isDirectory || f.isMergedTs) return true;
      final file = File(f.path);
      if (!file.existsSync()) return false;
      final size = f.size ?? (await file.length());
      if (size <= 0) return false;
      if (f.isImage) {
        if (size > 64 * 1024 * 1024) return true; // 超大图片跳过解码避免内存峰值
        return _isDecodableImage(file);
      }
      if (f.isVideo) {
        return _isUsableVideo(f);
      }
      // 音频等无可靠且低误判的完整校验，空文件已在上方过滤，这里保留。
    } catch (_) {
      return false;
    }
    return true;
  }

  /// 视频损坏校验：对新增/变更视频用原生插件读取容器信息，读不到即视为损坏
  Future<bool> _isUsableVideo(FileItem f) async {
    // 仅对容器可解析、且解析失败大概率即损坏的封装判定，避免误删 ts/rmvb 等
    const checkable = {'mp4', 'mkv', 'mov', '3gp', '3gpp'};
    if (!checkable.contains(f.extension)) return true;
    try {
      if (!MediaMetadata.isSupported(f.path)) return true;
      final md = await MediaMetadata.read(f.path);
      // 有实际大小却读不到容器信息 → 判定损坏
      return md != null;
    } catch (_) {
      return false;
    }
  }

  /// 尝试解码图片，失败即视为损坏
  Future<bool> _isDecodableImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }


  @override
  List<FileItem> getFilesForCategory(FileCategory category) {
    if (_categoryCache.containsKey(category.name)) {
      return _categoryCache[category.name]!;
    }

    final filtered =
        _pathCache.values.where((f) => category.matches(f)).toList();
    _categoryCache[category.name] = filtered;
    return filtered;
  }

  @override
  Future<bool> hasChanges(SharedContentSettings settings) async {
    if (kIsWeb) return false;

    final paths = _getScanPaths(settings);
    // 后台 Isolate 收集，避免大目录遍历阻塞 UI
    final found = await _collectFiles(paths);

    final currentKeys = found.values
        .map((e) => '${e.path}|${e.size}|${e.modified.millisecondsSinceEpoch}')
        .toSet();
    final cachedKeys = _pathCache.values
        .map((e) =>
            '${e.path}|${e.size ?? 0}|${e.modifiedAt?.millisecondsSinceEpoch ?? 0}')
        .toSet();

    if (currentKeys.length != cachedKeys.length) return true;
    return !cachedKeys.containsAll(currentKeys);
  }

  @override
  void clearCategoryCache(String categoryName) {
    _categoryCache.remove(categoryName);
  }

  @override
  void clearAllCaches() {
    // 共享设置变化导致扫描路径改变时，必须清空全部缓存，
    // 避免旧共享目录的文件残留。
    _pathCache.clear();
    _verified.clear();
    _categoryCache.clear();
    // 缩略图内存映射必须一并清空：磁盘缓存（thumb_*）被外部清空后，
    // 内存里残留的旧路径会指向已删除的文件，导致缩略图永远渲染失败
    // （远程设备访问本机缩略图时经 /thumb 接口也会命中此映射）
    _thumbnailCache.clear();
    _rejectedTs.clear();
    _scanSig = '';
    _loaded = false;
    // 记忆化的加载 Future 必须一并重置，否则下次 _ensureLoaded 会跳过
    // _loadFromDisk，磁盘状态与内存永远不同步
    _loadFuture = null;
    // 同步删除磁盘上的本地文件索引
    _deleteDiskIndex();
  }

  /// 重置内存缓存，但**保留磁盘索引**（下次扫描从磁盘重新加载复用）。
  ///
  /// 用于应用启动 / 共享设置变化时清掉进程内旧数据，同时不清空持久化缓存，
  /// 否则每次打开应用都会把磁盘索引删掉（缓存永远 0KB、也无法复用、每次都全量重扫）。
  ///
  /// 注意：必须同时重置 [_loadFuture]。_ensureLoaded 使用 `_loadFuture ??=`
  /// 记忆化，若只置 _loaded=false，下次扫描会复用旧的加载 Future 而**跳过
  /// 从磁盘重新加载索引**，导致缓存永远无法复用、每次都全量重校验。
  void resetMemoryCache() {
    _pathCache.clear();
    _verified.clear();
    _categoryCache.clear();
    _rejectedTs.clear(); // 随 _loadFromDisk 从磁盘索引恢复
    _scanSig = '';
    _loaded = false; // 下次扫描从磁盘重新加载
    _loadFuture = null; // 关键：让 _ensureLoaded 重新执行 _loadFromDisk
  }

  /// 删除本地文件索引磁盘缓存
  void _deleteDiskIndex() {
    AppCacheDirectory.root.then((dir) {
      final f = File('${dir.path}${Platform.pathSeparator}$_indexFileName');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 本地文件索引磁盘持久化
  // ---------------------------------------------------------------------------

  /// 从磁盘加载上次的本地文件索引（一次性，供"读缓存 + key 对比增量更新"使用）。
  ///
  /// 启动/首次扫描时把磁盘上保存的 [FileItem] 列表、已校验路径与扫描签名载入内存，
  /// 后续扫描据此复用未变化文件的缓存，只有新增/变更/删除才会更新并回写磁盘。
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loadFuture ??= _loadFromDisk();
    try {
      await _loadFuture;
    } finally {
      _loaded = true;
    }
  }

  /// 索引格式版本
  ///
  /// v2：ts 合并项校验升级为「TS 同步字节结构 + 真实播放」双层校验，
  /// 旧索引中经弱校验（仅探时长）通过的合并项需强制重新校验。
  static const int _indexVersion = 2;

  /// 在后台 Isolate 中读取并解码索引文件。
  ///
  /// 必须写成静态方法：闭包若定义在实例方法内会连带捕获本实例
  /// （含 [_loadFuture] 这类不可 sendable 的对象），
  /// 导致 `Illegal argument in isolate message: object is unsendable`。
  static dynamic _readIndexFileSync(String path) {
    final f = File(path);
    if (!f.existsSync()) return null;
    return jsonDecode(f.readAsStringSync());
  }

  /// 在后台 Isolate 中编码并写入索引文件（静态，理由同上）。
  static void _writeIndexFileSync(String path, Object payload) {
    File(path).writeAsStringSync(jsonEncode(payload), flush: true);
  }

  Future<void> _loadFromDisk() async {
    try {
      final dir = await AppCacheDirectory.root;
      final path = '${dir.path}${Platform.pathSeparator}$_indexFileName';
      // 大索引（数 MB JSON）的读取 + 解码放到后台 Isolate，避免阻塞 UI 线程。
      // 必须调用静态方法：若在闭包里直接写 IO，闭包会连带捕获本实例
      // （含 _loadFuture 等不可 sendable 对象），抛
      // "Illegal argument in isolate message: object is unsendable"。
      final dynamic decoded = await Isolate.run(() => _readIndexFileSync(path));
      if (decoded == null) return;
      final map = decoded as Map<String, dynamic>;
      final verified = (map['verified'] as List<dynamic>? ?? [])
          .cast<String>()
          .toSet();
      // 负缓存（旧索引无此字段 → 空，退化为校验一次后再记录）
      final rejected = map['rejectedTs'];
      if (rejected is Map<String, dynamic>) {
        _rejectedTs.clear();
        _rejectedTs.addAll(
          rejected.map((k, v) => MapEntry(k, v is String ? v : '')),
        );
        _rejectedTs.removeWhere((_, v) => v.isEmpty);
      }
      final items = (map['items'] as List<dynamic>? ?? [])
          .map((e) => _fileItemFromJson(e as Map<String, dynamic>))
          .toList();
      _verified.clear();
      _verified.addAll(verified);
      _pathCache.clear();
      for (final item in items) {
        _pathCache[item.path] = item;
      }
      // 旧版本索引：ts 合并项校验较弱，撤销其已校验标记，下次扫描重新做
      // 「结构 + 真实播放」双层校验，不可播放的合并项将被剔除并清理。
      // 同时删除旧版生成的 ts_merged_* 临时文件，否则 _validateMergedTs 的
      // 「同尺寸文件已存在」快速路径会绕过新校验直接放行。
      if ((map['v'] as int? ?? 1) < _indexVersion) {
        _verified.removeWhere((p) => _pathCache[p]?.isMergedTs ?? false);
        try {
          await for (final entity
              in Directory(dir.path).list(followLinks: false)) {
            final name = entity.uri.pathSegments.last;
            if (entity is File && name.startsWith('ts_merged_')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
      _scanSig = map['scanSig'] as String? ?? '';
    } catch (e) {
      debugPrint('[LocalCache] 加载本地文件索引失败: $e');
    }
  }

  /// 把当前内存缓存写入磁盘（异步，不阻塞扫描结果返回）
  Future<void> _persistCache() async {
    try {
      final dir = await AppCacheDirectory.root;
      final path = '${dir.path}${Platform.pathSeparator}$_indexFileName';
      final payload = {
        'v': _indexVersion,
        'scanSig': _scanSig,
        'verified': _verified.toList(),
        'rejectedTs': _rejectedTs,
        'items': _pathCache.values.map(_fileItemToJson).toList(),
      };
      // 大列表 JSON 编码（可达数十 MB 字符串构建）放到后台 Isolate，避免掉帧。
      // 同样调用静态方法，payload 为纯数据（深拷贝进 Isolate 即可）。
      await Isolate.run(() => _writeIndexFileSync(path, payload));
    } catch (e) {
      debugPrint('[LocalCache] 保存本地文件索引失败: $e');
    }
  }

  /// 本地文件索引中是否存在可复用的缓存（供宿主判断是否需要全量展示前加载）
  Future<bool> hasDiskCache() async {
    try {
      final dir = await AppCacheDirectory.root;
      return File('${dir.path}${Platform.pathSeparator}$_indexFileName')
          .existsSync();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _fileItemToJson(FileItem f) => {
        'name': f.name,
        'path': f.path,
        'isDirectory': f.isDirectory,
        'size': f.size,
        'modifiedAt': f.modifiedAt?.millisecondsSinceEpoch,
        'duration': f.duration,
        'tsFragments': f.tsFragments,
      };

  FileItem _fileItemFromJson(Map<String, dynamic> json) => FileItem(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDirectory: json['isDirectory'] as bool? ?? false,
        size: json['size'] as int?,
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['modifiedAt'] as int)
            : null,
        duration: json['duration'] as int?,
        tsFragments: (json['tsFragments'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );

  /// 从内存缓存中移除单个文件（删除文件后用，无需全量重扫即可更新列表）
  ///
  /// 同步清理缩略图磁盘缓存（确定性命名，重启后也能清）、媒体时长缓存
  /// 与各分类缓存，避免删除后残留在列表与缓存中。
  void removeFileFromCache(String path) {
    final item = _pathCache.remove(path);
    _verified.remove(path);
    _thumbnailCache.remove(path);
    if (item != null) {
      // 时长缓存联动清理
      MediaDurationService.instance.removeDurationsForFile(item.name, item.size);
    }
    // 缩略图磁盘文件；合并项额外清理合并临时文件
    AppCacheDirectory.root.then((dir) {
      if (item != null && item.isMergedTs) {
        try {
          final merged = File(
            '${dir.path}${Platform.pathSeparator}ts_merged_${path.hashCode}.ts',
          );
          if (merged.existsSync()) merged.deleteSync();
        } catch (_) {}
      }
      try {
        final f = File(
          '${dir.path}${Platform.pathSeparator}thumb_${path.hashCode}.jpg',
        );
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    });
    for (final key in _categoryCache.keys.toList()) {
      _categoryCache[key]?.removeWhere((f) => f.path == path);
    }
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

  /// 同步获取已生成的视频缩略图路径（未生成时返回 null）
  ///
  /// 供列表卡片**首帧**直接拿到缩略图路径渲染，避免「占位图 → 缩略图」
  /// 的闪烁：内存缓存未命中时按确定性命名（thumb_路径哈希.jpg）直查磁盘。
  String? peekThumbnail(String videoPath) {
    if (kIsWeb) return null;
    final cached = _thumbnailCache[videoPath];
    if (cached != null) return cached;
    final root = AppCacheDirectory.pinnedPath;
    if (root == null) return null;
    try {
      final thumb = File(
        '$root${Platform.pathSeparator}thumb_${videoPath.hashCode}.jpg',
      );
      if (!thumb.existsSync()) return null;
      _thumbnailCache[videoPath] = thumb.path;
      return thumb.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getVideoThumbnail(String videoPath) async {
    if (kIsWeb) return null;

    // 内存缓存命中：必须校验磁盘文件仍存在。
    // 用户在设置页清空缓存（或系统清理缓存目录）后，thumb_* 文件已被删除，
    // 若直接返回内存里的旧路径，调用方（列表卡片 / 远程设备 /thumb 接口）
    // 会拿到指向已删除文件的路径，缩略图永远渲染不出来。
    final cached = _thumbnailCache[videoPath];
    if (cached != null) {
      if (File(cached).existsSync()) return cached;
      _thumbnailCache.remove(videoPath); // 磁盘文件已被清除 → 失效并重新生成
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

    // 失败结果（null）不写入缓存：保证之后还能重试
    // （例如缓存目录刚被清空、解码器临时不可用等场景）
    if (result != null) {
      _thumbnailCache[videoPath] = result;
    }
    return result;
  }
}
