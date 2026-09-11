import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/providers/global_providers.dart';
import '../../../core/services/storage_service.dart';
import '../../device_discovery/providers/device_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/file_category.dart';
import '../models/file_item.dart';
import '../services/download_service.dart';
import '../services/file_cache_service.dart';
import '../services/local_file_service.dart';
import '../services/media_duration_service.dart';
import '../services/remote_file_service.dart';

// ===========================================================================
// 设备选择
// ===========================================================================

/// 用户手动选中的设备
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, String?>(
      SelectedDeviceNotifier.new,
    );

class SelectedDeviceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  set device(String? value) => state = value;
}

/// 当前已连接的设备列表（过滤出 WebSocket 已建立的设备）
final connectedDevicesProvider = Provider<List<Device>>((ref) {
  final allDevices = ref.watch(previouslyConnectedDevicesProvider);
  final connStates = ref.watch(connectionStatesProvider);
  return allDevices
      .where((d) => connStates[d.id] == DeviceConnectionState.connected)
      .toList();
});

/// 实际生效的选中设备
final effectiveSelectedDeviceProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedDeviceProvider);
  final connectedDevices = ref.watch(connectedDevicesProvider);

  if (selected != null) {
    if (selected == '本机') return null;
    final stillConnected = connectedDevices.any((d) => d.name == selected);
    if (stillConnected) return selected;
  }

  if (connectedDevices.isNotEmpty) {
    return connectedDevices.first.name;
  }
  return null;
});

/// 选中设备的 IP 地址（null 表示本机）
final selectedDeviceIpProvider = Provider<String?>((ref) {
  final deviceName = ref.watch(effectiveSelectedDeviceProvider);
  if (deviceName == null) return null;
  final connectedDevices = ref.watch(connectedDevicesProvider);
  final device = connectedDevices.firstWhere(
    (d) => d.name == deviceName,
    orElse: () => connectedDevices.first,
  );
  return device.ip;
});

/// 是否正在浏览远程设备文件
final isRemoteBrowsingProvider = Provider<bool>((ref) {
  return ref.watch(effectiveSelectedDeviceProvider) != null;
});

/// 远程文件服务实例
final remoteFileServiceProvider = Provider<RemoteFileService>((ref) {
  return RemoteFileService.instance;
});

/// 持久下载服务实例
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService.instance;
  service.init(ref.read(sharedPrefsProvider));
  return service;
});

/// 媒体时长探测服务实例
final mediaDurationServiceProvider = Provider<MediaDurationService>((ref) {
  final service = MediaDurationService.instance;
  service.init(ref.read(sharedPrefsProvider));
  return service;
});

/// 下载进度状态（key = 文件 uniqueKey，value = 0.0~1.0）
final downloadProgressProvider =
    NotifierProvider<DownloadProgressNotifier, Map<String, double>>(
      DownloadProgressNotifier.new,
    );

class DownloadProgressNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  bool isDownloading(String key) => state.containsKey(key);

  void start(String key) {
    state = {...state, key: 0.0};
  }

  void update(String key, double progress) {
    state = {...state, key: progress};
  }

  void end(String key) {
    if (!state.containsKey(key)) return;
    final next = Map<String, double>.from(state)..remove(key);
    state = next;
  }
}

// ===========================================================================
// 路径
// ===========================================================================

final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '/';

  set path(String value) => state = value;
}

// ===========================================================================
// 文件分类
// ===========================================================================

/// 默认分类列表
final defaultCategories = <FileCategory>[
  const FileCategory(
    name: AppStrings.categoryImage,
    icon: Icons.image,
    fileTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic'],
  ),
  const FileCategory(
    name: AppStrings.categoryVideo,
    icon: Icons.video_file,
    fileTypes: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'rmvb', 'ts', '3gp'],
  ),
  const FileCategory(
    name: AppStrings.categoryAudio,
    icon: Icons.audio_file,
    fileTypes: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'],
  ),
  const FileCategory(
    name: AppStrings.categoryText,
    icon: Icons.description,
    fileTypes: ['txt', 'md', 'log', 'rtf'],
  ),
  const FileCategory(
    name: AppStrings.categoryWord,
    icon: Icons.description,
    fileTypes: ['doc', 'docx'],
  ),
  const FileCategory(
    name: AppStrings.categoryExcel,
    icon: Icons.table_chart,
    fileTypes: ['xls', 'xlsx', 'csv'],
  ),
  const FileCategory(
    name: AppStrings.categoryPpt,
    icon: Icons.slideshow,
    fileTypes: ['ppt', 'pptx'],
  ),
  const FileCategory(
    name: AppStrings.categoryPdf,
    icon: Icons.picture_as_pdf,
    fileTypes: ['pdf'],
  ),
  const FileCategory(
    name: AppStrings.categoryArchive,
    icon: Icons.folder_zip,
    fileTypes: ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'],
  ),
];

/// 自定义分类列表（持久化）
final customCategoriesProvider =
    NotifierProvider<CustomCategoriesNotifier, List<FileCategory>>(
      CustomCategoriesNotifier.new,
    );

class CustomCategoriesNotifier extends Notifier<List<FileCategory>> {
  @override
  List<FileCategory> build() {
    final prefs = ref.read(sharedPrefsProvider);
    final jsonStr = prefs.getString(StorageKeys.customCategories);
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        return list
            .map((e) => FileCategory.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // 解析失败，回退到空列表
      }
    }
    return const [];
  }

  void _persist() {
    final jsonStr = jsonEncode(state.map((c) => c.toJson()).toList());
    ref.read(sharedPrefsProvider).setString(StorageKeys.customCategories, jsonStr);
  }

  void addCategory(FileCategory category) {
    if (state.any((c) => c.name == category.name)) return;
    state = [...state, category];
    _persist();
    // 自动选中新分类
    ref.read(fileCategoryProvider.notifier).category = category.name;
  }

  void removeCategory(String name) {
    state = state.where((c) => c.name != name).toList();
    _persist();
    // 清除该分类的文件缓存
    ref.read(localFileServiceProvider).clearCategoryCache(name);
    // 如果删除的是当前选中的分类，回退到第一个默认分类
    final currentCategory = ref.read(fileCategoryProvider);
    if (currentCategory == name) {
      final fallback = defaultCategories.first.name;
      ref.read(fileCategoryProvider.notifier).category = fallback;
    }
  }

  void updateCategory(FileCategory category) {
    state = state.map((c) => c.name == category.name ? category : c).toList();
    _persist();
  }
}

/// 所有分类（默认 + 自定义）
final allCategoriesProvider = Provider<List<FileCategory>>((ref) {
  final defaults = defaultCategories;
  final customs = ref.watch(customCategoriesProvider);
  return [...defaults, ...customs];
});

/// 当前选中的分类
final fileCategoryProvider = NotifierProvider<FileCategoryNotifier, String>(
  FileCategoryNotifier.new,
);

class FileCategoryNotifier extends Notifier<String> {
  @override
  String build() => AppStrings.categoryImage;

  set category(String value) => state = value;
}

// ===========================================================================
// 显示模式（文件名显示、时间轴分组、后缀分组、排序方向）
// ===========================================================================

/// 文件名显示开关
final showFileNameProvider =
    NotifierProvider<ShowFileNameNotifier, bool>(
      ShowFileNameNotifier.new,
    );

class ShowFileNameNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(StorageKeys.filterShowFileName) ??
      true;

  set value(bool v) {
    state = v;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.filterShowFileName, v);
  }

  void toggle() => value = !state;
}

/// 时间轴分组开关
final timelineGroupProvider =
    NotifierProvider<TimelineGroupNotifier, bool>(
      TimelineGroupNotifier.new,
    );

class TimelineGroupNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(StorageKeys.filterTimelineGroup) ??
      false;

  set value(bool v) {
    state = v;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.filterTimelineGroup, v);
  }

  void toggle() => value = !state;
}

/// 后缀名分组开关（默认开启）
final extensionGroupProvider =
    NotifierProvider<ExtensionGroupNotifier, bool>(
      ExtensionGroupNotifier.new,
    );

class ExtensionGroupNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(StorageKeys.filterExtensionGroup) ??
      true;

  set value(bool v) {
    state = v;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.filterExtensionGroup, v);
  }

  void toggle() => value = !state;
}

/// 排序方向开关（默认 false = 倒序/最新在前，true = 正序/最旧在前）
final sortAscendingProvider =
    NotifierProvider<SortAscendingNotifier, bool>(
      SortAscendingNotifier.new,
    );

class SortAscendingNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(StorageKeys.filterSortAscending) ??
      false;

  set value(bool v) {
    state = v;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.filterSortAscending, v);
  }

  void toggle() => value = !state;
}

/// 仅显示本设备下载的文件开关（默认关闭）
///
/// 浏览本机时匹配任意设备来源的下载记录；浏览远程设备时只匹配该设备。
final onlyDownloadedProvider =
    NotifierProvider<OnlyDownloadedNotifier, bool>(OnlyDownloadedNotifier.new);

/// 下载状态变更版本号：删除/新增下载副本时自增，
/// 让依赖 `DownloadService.hasDownloadRecord` 的过滤链重新计算（仅下载过滤）。
final downloadedStampProvider =
    NotifierProvider<DownloadStampNotifier, int>(DownloadStampNotifier.new);

class DownloadStampNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 下载状态变化时调用，触发"仅下载"过滤重新计算
  void bump() => state++;
}

class OnlyDownloadedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(StorageKeys.filterOnlyDownloaded) ??
      false;

  set value(bool v) {
    state = v;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.filterOnlyDownloaded, v);
  }

  void toggle() => value = !state;
}

// ===========================================================================
// 布局模式
// ===========================================================================

/// 桌面端侧边栏列数模式
enum ColumnMode { single, double }

final desktopColumnModeProvider =
    NotifierProvider<DesktopColumnModeNotifier, ColumnMode>(
      DesktopColumnModeNotifier.new,
    );

class DesktopColumnModeNotifier extends Notifier<ColumnMode> {
  @override
  ColumnMode build() {
    final name = ref.read(sharedPrefsProvider).getString(StorageKeys.desktopColumnMode);
    return ColumnMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ColumnMode.single,
    );
  }

  set mode(ColumnMode value) {
    state = value;
    ref.read(sharedPrefsProvider).setString(StorageKeys.desktopColumnMode, value.name);
  }
}

/// 手机端分类显示模式
enum CategoryDisplayMode { dropdown, list }

final mobileCategoryDisplayModeProvider =
    NotifierProvider<MobileCategoryDisplayModeNotifier, CategoryDisplayMode>(
      MobileCategoryDisplayModeNotifier.new,
    );

class MobileCategoryDisplayModeNotifier extends Notifier<CategoryDisplayMode> {
  @override
  CategoryDisplayMode build() {
    final name = ref.read(sharedPrefsProvider).getString(StorageKeys.mobileCategoryDisplayMode);
    return CategoryDisplayMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => CategoryDisplayMode.list,
    );
  }

  set mode(CategoryDisplayMode value) {
    state = value;
    ref.read(sharedPrefsProvider).setString(StorageKeys.mobileCategoryDisplayMode, value.name);
  }
}

// ===========================================================================
// 文件服务 & 扫描状态
// ===========================================================================

/// 本机文件服务实例
final localFileServiceProvider = Provider<LocalFileService>((ref) {
  return LocalFileService.instance;
});

/// 文件扫描状态
enum FileScanState { idle, scanning, done, empty }

final fileScanStateProvider =
    NotifierProvider<FileScanStateNotifier, FileScanState>(
      FileScanStateNotifier.new,
    );

class FileScanStateNotifier extends Notifier<FileScanState> {
  @override
  FileScanState build() => FileScanState.idle;

  void set(FileScanState value) => state = value;
}

// ===========================================================================
// 文件列表（从共享文件夹扫描真实文件）
// ===========================================================================

final fileListProvider = NotifierProvider<FileListNotifier, List<FileItem>>(
  FileListNotifier.new,
);

class FileListNotifier extends Notifier<List<FileItem>> {
  /// 扫描代号：每次新扫描 +1，用于让过期的后台渐进回调不影响当前结果
  int _scanSeq = 0;

  /// 本 notifier 是否仍存活（dispose 后禁止再赋值 state / read）
  ///
  /// 设备切换会触发 provider 重建（新实例），旧实例上挂起的异步回调
  /// （渐进扫描 onProgress、await 之后的赋值）若继续写 state 会出错。
  bool _alive = true;

  @override
  List<FileItem> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    // Watch 共享内容设置 — 设置变化时 Notifier 自动重建，触发重新扫描
    final settings = ref.watch(sharedContentProvider);
    // Watch 选中设备 — 设备切换时自动重新加载文件列表
    final deviceIp = ref.watch(selectedDeviceIpProvider);
    // 仅当共享设置变化（缓存签名不新鲜）时重置**内存**缓存，避免设备切换时误清本地缓存引发重扫。
    // 注意：不能清空磁盘索引，否则每次启动都会把持久化缓存删掉、无法复用。
    if (!ref.read(localFileServiceProvider).isCacheFresh(settings)) {
      ref.read(localFileServiceProvider).resetMemoryCache();
    }
    // 触发扫描（本机或远程）
    Future.microtask(() => scanFiles(deviceIp));
    return [];
  }

  /// 扫描文件（本机或远程）
  ///
  /// 远程设备采用 **缓存优先 + 后台增量同步** 策略：
  /// 1. 先尝试读取本地缓存的文件列表，若有则立即返回（避免等待）
  /// 2. 后台拉取最新列表，与缓存做 uniqueKey 差集对比
  /// 3. 若有变化才更新 state；无变化则保持当前列表（避免无谓 rebuild）
  /// 4. 首次访问无缓存时，正常显示 loading 状态直到拉取完成
  /// [force] true 时跳过缓存复用，强制重处理当前分类全部文件。
  /// [checkReady] false 时始终重扫当前分类（但仍复用未变化文件），
  /// 用于刷新按钮：既能发现新增/删除/变更，又不回退成全量重处理。
  Future<void> scanFiles(
    String? deviceIp, {
    bool force = false,
    bool checkReady = true,
  }) async {
    final scanStateNotifier = ref.read(fileScanStateProvider.notifier);

    if (deviceIp == null) {
      // 本机文件：优先复用缓存，只对当前分类做增量扫描（跳过未变化文件的
      // 缩略图/解码/时长等重处理），避免每次切换/刷新全量扫描造成卡顿。
      final settings = ref.read(sharedContentProvider);
      final service = ref.read(localFileServiceProvider);
      final category = _currentCategory();

      if (!force &&
          checkReady &&
          (category == null
              ? service.isCacheFresh(settings)
              : service.isCategoryDataReady(category))) {
        state = service.masterFileList;
        scanStateNotifier.set(FileScanState.done);
        return;
      }

      scanStateNotifier.set(FileScanState.scanning);
      // 渐进扫描：先快速返回列表立即渲染，后台分批校验并增量刷新；
      // 用 seq 防止过期的后台校验回调覆盖当前扫描结果
      final seq = ++_scanSeq;
      final files = await service.scanFilesProgressive(
        settings,
        category: category,
        force: force,
        onProgress: (_, __, partial) {
          if (_alive && _scanSeq == seq) state = partial;
        },
      );
      if (_alive && _scanSeq == seq) {
        state = files;
        scanStateNotifier.set(
          files.isEmpty ? FileScanState.empty : FileScanState.done,
        );
      }
      return;
    }

    // 远程设备：缓存优先策略
    final remoteService = ref.read(remoteFileServiceProvider);
    // 进入远程分支即自增扫描代号，作废可能仍在本机分支进行中的渐进扫描：
    // 重开应用后本机会先扫一次（若本机索引缺失则为耗时全量扫描，seq=N），
    // 随后自动连上远程设备切到本分支。若不递增，残留本机扫描的 onProgress
    // （_scanSeq 仍为 N）会持续把本机文件写回 state，覆盖远程列表，
    // 表现为「远程列表一闪 → 变成本机列表」。点刷新走无缓存分支重拉才恢复。
    final seq = ++_scanSeq;
    final cached = await remoteService.getCachedFileList(deviceIp);
    if (!_alive || _scanSeq != seq) return;

    if (cached != null && cached.isNotEmpty) {
      // 立即显示缓存数据，无需 loading
      state = cached;
      scanStateNotifier.set(FileScanState.done);

      // 后台拉取最新列表，做增量对比
      _syncRemoteInBackground(deviceIp, cached);
      return;
    }

    // 无缓存：正常显示 loading，等待首次拉取
    scanStateNotifier.set(FileScanState.scanning);
    final files = await remoteService.fetchRemoteFileList(deviceIp);
    // 拉取期间可能已切换设备/派生了新的扫描：过期结果不得覆盖当前上下文
    if (!_alive || _scanSeq != seq) return;
    state = files;
    scanStateNotifier.set(
      files.isEmpty ? FileScanState.empty : FileScanState.done,
    );
  }

  /// 后台增量同步远程文件列表
  ///
  /// 拉取最新列表后与缓存对比，仅在发生变化时更新 state。
  Future<void> _syncRemoteInBackground(
    String deviceIp,
    List<FileItem> cachedFiles,
  ) async {
    try {
      final remoteService = ref.read(remoteFileServiceProvider);
      final latest = await remoteService.fetchRemoteFileList(deviceIp);

      // 设备可能已切换，确认仍是同一设备
      final currentIp = ref.read(selectedDeviceIpProvider);
      if (!_alive || currentIp != deviceIp) return;

      if (FileCacheService.instance.hasChanges(cachedFiles, latest)) {
        state = latest;
      }
      // 无变化则保持当前 state，避免无谓 rebuild
    } catch (e) {
      // 后台同步失败静默处理，下次再试
      debugPrint('[FileListNotifier] 后台同步远程文件失败: $e');
    }
  }

  /// 检查文件变更并按需刷新（选择分类时调用）
  ///
  /// 本机分支只对**当前选中分类**做增量扫描：分类数据尚未缓存就走一次
  /// （cheap：未变化文件直接复用，跳过重处理）；已缓存则直接跳过，
  /// 避免切换分类时全量扫描造成卡顿。删除的文件也会在此过程中被同步移除。
  Future<void> refreshIfNeeded() async {
    final deviceIp = ref.read(selectedDeviceIpProvider);
    if (deviceIp == null) {
      final service = ref.read(localFileServiceProvider);
      final category = _currentCategory();
      if (category != null && !service.isCategoryDataReady(category)) {
        await scanFiles(null, force: false);
      }
    } else {
      // 远程文件：触发后台增量同步（不阻塞 UI）
      final cached = await ref
          .read(remoteFileServiceProvider)
          .getCachedFileList(deviceIp);
      if (cached != null) {
        await _syncRemoteInBackground(deviceIp, cached);
      } else {
        await scanFiles(deviceIp);
      }
    }
  }

  /// 强制重新扫描当前分类（用户点击刷新按钮时调用）
  ///
  /// 本机：对当前分类强制重扫（重新做可用性/删除检测，未变化的文件仍复用缓存）。
  /// 远程：清除该设备缓存后强制重新拉取，确保显示最新文件列表。
  Future<void> forceRefresh() async {
    final deviceIp = ref.read(selectedDeviceIpProvider);
    if (deviceIp == null) {
      // 本机：始终重扫当前分类（checkReady:false 绕过"数据就绪即跳过"），
      // 但复用未变化文件缓存，因此能发现新增/删除/变更，又不全量重处理。
      await scanFiles(null, checkReady: false);
    } else {
      // 远程：清除该设备缓存后强制重新拉取（显示 loading）
      await FileCacheService.instance.clearCache(deviceIp);
      await scanFiles(deviceIp);
    }
  }

  /// 解析当前选中的分类（不存在时返回 null）
  FileCategory? _currentCategory() {
    final name = ref.read(fileCategoryProvider);
    return ref
        .read(allCategoriesProvider)
        .where((c) => c.name == name)
        .firstOrNull;
  }
}

/// 根据分类筛选后的文件列表（未排序，作为分组缓存的基础）
///
/// 仅依赖文件列表和分类，不依赖排序方向。
/// 当排序方向变化时，此 provider 不会重算，从而避免分组重新计算。
final _categoryFilteredFileListProvider = Provider<List<FileItem>>((ref) {
  final allFiles = ref.watch(fileListProvider);
  final categories = ref.watch(allCategoriesProvider);
  final selectedCategory = ref.watch(fileCategoryProvider);
  final onlyDownloaded = ref.watch(onlyDownloadedProvider);
  final currentDevice = ref.watch(effectiveSelectedDeviceProvider);
  // 监听下载版本号：删除/新增下载文件时强制重新计算仅下载过滤
  ref.watch(downloadedStampProvider);

  // 开启"仅显示下载文件"时，先按下载记录过滤（本机=任意设备，远程=当前设备）
  var result = allFiles;
  if (onlyDownloaded) {
    result = allFiles
        .where((f) => DownloadService.instance.hasDownloadRecord(
              deviceName: currentDevice,
              fileName: f.name,
              size: f.size,
            ))
        .toList();
  }

  final category = categories.where((c) => c.name == selectedCategory).firstOrNull;
  if (category == null) return result;
  return result.where((f) => category.matches(f)).toList();
});

/// 根据分类筛选并排序后的文件列表（用于平铺展示）
final filteredFileListProvider = Provider<List<FileItem>>((ref) {
  final filtered = ref.watch(_categoryFilteredFileListProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  final sorted = List<FileItem>.from(filtered);
  sorted.sort((a, b) {
    final aTime = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
    return sortAscending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
  });

  return sorted;
});

/// 时间轴分组数据
class TimelineGroup {
  final String label;
  final List<FileItem> files;

  const TimelineGroup({required this.label, required this.files});
}

/// 后缀名分组数据
class ExtensionGroup {
  final String label;
  final List<FileItem> files;

  const ExtensionGroup({required this.label, required this.files});
}

/// 时间轴 + 后缀嵌套分组数据（时间轴优先，外层时间轴，内层后缀）
class NestedTimelineGroup {
  final String label;
  final List<ExtensionGroup> extensionGroups;

  const NestedTimelineGroup({required this.label, required this.extensionGroups});
}

/// 原始时间轴分组（不依赖排序方向，仅依赖文件列表）
///
/// 遍历所有文件进行分组是耗时操作，缓存此结果避免排序变化时重算。
/// 包含每组的最大时间用于后续排序。
class _RawTimelineGroup {
  final Map<String, List<FileItem>> groups;
  final Map<String, int> maxTimes;
  const _RawTimelineGroup(this.groups, this.maxTimes);
}

final _rawTimelineGroupProvider = Provider<_RawTimelineGroup>((ref) {
  final files = ref.watch(_categoryFilteredFileListProvider);
  final now = DateTime.now();

  final groups = <String, List<FileItem>>{};
  final maxTimes = <String, int>{};

  for (final file in files) {
    final date = file.modifiedAt ?? now;
    final label = _timelineLabel(date, now);
    groups.putIfAbsent(label, () => []).add(file);
    final t = date.millisecondsSinceEpoch;
    if (!maxTimes.containsKey(label) || t > maxTimes[label]!) {
      maxTimes[label] = t;
    }
  }

  return _RawTimelineGroup(groups, maxTimes);
});

/// 原始后缀分组（不依赖排序方向，仅依赖文件列表）
class _RawExtensionGroup {
  final Map<String, List<FileItem>> groups;
  final Map<String, int> maxTimes;
  const _RawExtensionGroup(this.groups, this.maxTimes);
}

final _rawExtensionGroupProvider = Provider<_RawExtensionGroup>((ref) {
  final files = ref.watch(_categoryFilteredFileListProvider);

  final groups = <String, List<FileItem>>{};
  final maxTimes = <String, int>{};

  for (final file in files) {
    final ext = file.extension.toUpperCase();
    groups.putIfAbsent(ext, () => []).add(file);
    final t = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
    if (!maxTimes.containsKey(ext) || t > maxTimes[ext]!) {
      maxTimes[ext] = t;
    }
  }

  return _RawExtensionGroup(groups, maxTimes);
});

/// 按时间轴分组的文件列表（仅对组标签排序，廉价操作）
final timelineGroupedFileListProvider = Provider<List<TimelineGroup>>((ref) {
  final raw = ref.watch(_rawTimelineGroupProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  final sortedLabels = raw.maxTimes.keys.toList()
    ..sort((a, b) => sortAscending
        ? raw.maxTimes[a]!.compareTo(raw.maxTimes[b]!)
        : raw.maxTimes[b]!.compareTo(raw.maxTimes[a]!));

  return sortedLabels
      .map((label) => TimelineGroup(label: label, files: raw.groups[label]!))
      .toList();
});

/// 按后缀名分组的文件列表（仅对组标签排序，廉价操作）
final extensionGroupedFileListProvider = Provider<List<ExtensionGroup>>((ref) {
  final raw = ref.watch(_rawExtensionGroupProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  final sortedLabels = raw.maxTimes.keys.toList()
    ..sort((a, b) => sortAscending
        ? raw.maxTimes[a]!.compareTo(raw.maxTimes[b]!)
        : raw.maxTimes[b]!.compareTo(raw.maxTimes[a]!));

  return sortedLabels
      .map((ext) => ExtensionGroup(label: ext, files: raw.groups[ext]!))
      .toList();
});

/// 时间轴 + 后缀嵌套分组（先按时间轴分组，再在每组内按后缀分组）
final nestedGroupedFileListProvider = Provider<List<NestedTimelineGroup>>((ref) {
  final rawTimeline = ref.watch(_rawTimelineGroupProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  // 时间轴组排序
  final sortedTimelineLabels = rawTimeline.maxTimes.keys.toList()
    ..sort((a, b) => sortAscending
        ? rawTimeline.maxTimes[a]!.compareTo(rawTimeline.maxTimes[b]!)
        : rawTimeline.maxTimes[b]!.compareTo(rawTimeline.maxTimes[a]!));

  return sortedTimelineLabels.map((label) {
    final timelineFiles = rawTimeline.groups[label]!;

    // 在每个时间轴组内按后缀分组
    final extGroups = <String, List<FileItem>>{};
    final extMaxTimes = <String, int>{};

    for (final file in timelineFiles) {
      final ext = file.extension.toUpperCase();
      extGroups.putIfAbsent(ext, () => []).add(file);
      final t = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
      if (!extMaxTimes.containsKey(ext) || t > extMaxTimes[ext]!) {
        extMaxTimes[ext] = t;
      }
    }

    final sortedExts = extMaxTimes.keys.toList()
      ..sort((a, b) => sortAscending
          ? extMaxTimes[a]!.compareTo(extMaxTimes[b]!)
          : extMaxTimes[b]!.compareTo(extMaxTimes[a]!));

    return NestedTimelineGroup(
      label: label,
      extensionGroups: sortedExts
          .map((ext) => ExtensionGroup(label: ext, files: extGroups[ext]!))
          .toList(),
    );
  }).toList();
});

/// 预热分组缓存
///
/// 始终 watch 原始分组 provider，确保切换分组开关时无需重新遍历文件。
/// 视图层应始终 watch 此 provider。
final groupCacheWarmupProvider = Provider<void>((ref) {
  ref.watch(_rawTimelineGroupProvider);
  ref.watch(_rawExtensionGroupProvider);
});

/// 生成时间轴分组标签
String _timelineLabel(DateTime date, DateTime now) {
  final diff = now.difference(date);
  if (diff.inDays < 1) return '今天';
  if (diff.inDays < 2) return '昨天';
  if (diff.inDays < 7) return '本周';
  if (date.year == now.year && date.month == now.month) return '本月';
  if (date.year == now.year) {
    return '${date.month}月';
  }
  return '${date.year}年';
}
