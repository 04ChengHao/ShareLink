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
import '../services/local_file_service.dart';

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
  @override
  List<FileItem> build() {
    // Watch 共享内容设置 — 设置变化时 Notifier 自动重建，触发重新扫描
    ref.watch(sharedContentProvider);
    // 清除所有分类缓存，确保用新路径重新扫描
    ref.read(localFileServiceProvider).clearAllCaches();
    // 触发扫描
    Future.microtask(() => scanFiles());
    return [];
  }

  /// 扫描共享文件夹，更新文件列表
  Future<void> scanFiles() async {
    final settings = ref.read(sharedContentProvider);
    final service = ref.read(localFileServiceProvider);

    ref.read(fileScanStateProvider.notifier).set(FileScanState.scanning);

    final files = await service.scanFiles(settings);
    state = files;

    if (files.isEmpty) {
      ref.read(fileScanStateProvider.notifier).set(FileScanState.empty);
    } else {
      ref.read(fileScanStateProvider.notifier).set(FileScanState.done);
    }
  }

  /// 检查文件变更并按需刷新（选择分类时调用）
  Future<void> refreshIfNeeded() async {
    final settings = ref.read(sharedContentProvider);
    final service = ref.read(localFileServiceProvider);

    if (await service.hasChanges(settings)) {
      await scanFiles();
    }
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

  final category = categories.where((c) => c.name == selectedCategory).firstOrNull;
  if (category == null) return allFiles;
  return allFiles.where((f) => category.matches(f)).toList();
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
