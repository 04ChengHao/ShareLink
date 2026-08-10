import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/providers/global_providers.dart';
import '../../../core/services/storage_service.dart';
import '../../device_discovery/providers/device_provider.dart';
import '../models/file_category.dart';
import '../models/file_item.dart';

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
    fileTypes: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'rmvb', 'ts'],
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
  }

  void removeCategory(String name) {
    state = state.where((c) => c.name != name).toList();
    _persist();
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
// 显示模式（文件名显示、时间轴分组、大小排序）
// ===========================================================================

/// 文件名显示开关
final showFileNameProvider =
    NotifierProvider<ShowFileNameNotifier, bool>(
      ShowFileNameNotifier.new,
    );

class ShowFileNameNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  set value(bool v) => state = v;

  void toggle() => state = !state;
}

/// 时间轴分组开关
final timelineGroupProvider =
    NotifierProvider<TimelineGroupNotifier, bool>(
      TimelineGroupNotifier.new,
    );

class TimelineGroupNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  set value(bool v) => state = v;

  void toggle() => state = !state;
}

/// 后缀名分组开关（默认开启）
final extensionGroupProvider =
    NotifierProvider<ExtensionGroupNotifier, bool>(
      ExtensionGroupNotifier.new,
    );

class ExtensionGroupNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  set value(bool v) => state = v;

  void toggle() => state = !state;
}

/// 排序方向开关（默认 false = 倒序/最新在前，true = 正序/最旧在前）
final sortAscendingProvider =
    NotifierProvider<SortAscendingNotifier, bool>(
      SortAscendingNotifier.new,
    );

class SortAscendingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  set value(bool v) => state = v;

  void toggle() => state = !state;
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
  ColumnMode build() => ColumnMode.single;

  set mode(ColumnMode value) => state = value;
}

/// 手机端分类显示模式
enum CategoryDisplayMode { dropdown, list }

final mobileCategoryDisplayModeProvider =
    NotifierProvider<MobileCategoryDisplayModeNotifier, CategoryDisplayMode>(
      MobileCategoryDisplayModeNotifier.new,
    );

class MobileCategoryDisplayModeNotifier extends Notifier<CategoryDisplayMode> {
  @override
  CategoryDisplayMode build() => CategoryDisplayMode.list;

  set mode(CategoryDisplayMode value) => state = value;
}

// ===========================================================================
// 文件列表（静态测试数据）
// ===========================================================================

final fileListProvider = NotifierProvider<FileListNotifier, List<FileItem>>(
  FileListNotifier.new,
);

class FileListNotifier extends Notifier<List<FileItem>> {
  @override
  List<FileItem> build() {
    // TODO: 从共享文件夹获取真实文件列表
    final now = DateTime.now();
    return [
      FileItem(name: '风景.jpg', path: '/风景.jpg', size: 2456789, modifiedAt: now),
      FileItem(name: '截图.png', path: '/截图.png', size: 567432, modifiedAt: now.subtract(const Duration(days: 3))),
      FileItem(name: '头像.jpg', path: '/头像.jpg', size: 89234, modifiedAt: now.subtract(const Duration(days: 10))),
      FileItem(name: '设计稿.png', path: '/设计稿.png', size: 3456789, modifiedAt: now.subtract(const Duration(days: 45))),
      FileItem(name: '壁纸.jpg', path: '/壁纸.jpg', size: 7890123, modifiedAt: now.subtract(const Duration(days: 80))),
      FileItem(name: '相册1.jpg', path: '/相册1.jpg', size: 123456, modifiedAt: now.subtract(const Duration(days: 100))),
      FileItem(name: '旅行视频.mp4', path: '/旅行视频.mp4', size: 56789012, modifiedAt: now.subtract(const Duration(days: 200))),
      FileItem(name: '教程.mov', path: '/教程.mov', size: 23456789, modifiedAt: now.subtract(const Duration(days: 365))),
      FileItem(name: '音乐.mp3', path: '/音乐.mp3', size: 4567890, modifiedAt: now.subtract(const Duration(days: 400))),
      FileItem(name: '笔记.txt', path: '/笔记.txt', size: 2345, modifiedAt: now.subtract(const Duration(days: 500))),
      FileItem(name: 'README.md', path: '/README.md', size: 5678, modifiedAt: now.subtract(const Duration(days: 700))),
      FileItem(name: '报告.docx', path: '/报告.docx', size: 67890, modifiedAt: now.subtract(const Duration(days: 15))),
      FileItem(name: '合同.doc', path: '/合同.doc', size: 45678, modifiedAt: now.subtract(const Duration(days: 60))),
      FileItem(name: '预算表.xlsx', path: '/预算表.xlsx', size: 34567, modifiedAt: now.subtract(const Duration(days: 120))),
      FileItem(name: '演示.pptx', path: '/演示.pptx', size: 1234567, modifiedAt: now.subtract(const Duration(days: 250))),
      FileItem(name: '手册.pdf', path: '/手册.pdf', size: 890123, modifiedAt: now.subtract(const Duration(days: 380))),
      FileItem(name: '项目.zip', path: '/项目.zip', size: 45678901, modifiedAt: now.subtract(const Duration(days: 550))),
      FileItem(name: '源码.rar', path: '/源码.rar', size: 23456789, modifiedAt: now.subtract(const Duration(days: 720))),
      FileItem(name: 'main.dart', path: '/main.dart', size: 4567, modifiedAt: now.subtract(const Duration(days: 5))),
      FileItem(name: 'config.json', path: '/config.json', size: 1234, modifiedAt: now.subtract(const Duration(days: 20))),
      FileItem(name: 'app.apk', path: '/app.apk', size: 34567890, modifiedAt: now.subtract(const Duration(days: 300))),
      FileItem(name: '数据.csv', path: '/数据.csv', size: 5678, modifiedAt: now.subtract(const Duration(days: 90))),
    ];
  }

  set files(List<FileItem> value) => state = value;
}

/// 根据分类筛选并排序后的文件列表
final filteredFileListProvider = Provider<List<FileItem>>((ref) {
  final allFiles = ref.watch(fileListProvider);
  final categories = ref.watch(allCategoriesProvider);
  final selectedCategory = ref.watch(fileCategoryProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  // 筛选
  final category = categories.where((c) => c.name == selectedCategory).firstOrNull;
  List<FileItem> filtered;
  if (category == null) {
    filtered = allFiles;
  } else {
    filtered = allFiles.where((f) => category.matches(f)).toList();
  }

  // 排序：按修改时间，方向由 sortAscending 决定
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

/// 按时间轴分组的文件列表（按每组最新文件时间排序，方向由 sortAscending 决定）
final timelineGroupedFileListProvider = Provider<List<TimelineGroup>>((ref) {
  final files = ref.watch(filteredFileListProvider);
  final now = DateTime.now();
  final sortAscending = ref.watch(sortAscendingProvider);

  final groups = <String, List<FileItem>>{};
  final groupMaxTime = <String, int>{};

  for (final file in files) {
    final date = file.modifiedAt ?? now;
    final label = _timelineLabel(date, now);
    if (!groups.containsKey(label)) {
      groups[label] = [];
      groupMaxTime[label] = date.millisecondsSinceEpoch;
    } else {
      final t = date.millisecondsSinceEpoch;
      if (t > groupMaxTime[label]!) {
        groupMaxTime[label] = t;
      }
    }
    groups[label]!.add(file);
  }

  // 按每组最新文件时间排序
  final sortedLabels = groupMaxTime.keys.toList()
    ..sort((a, b) => sortAscending
        ? groupMaxTime[a]!.compareTo(groupMaxTime[b]!)
        : groupMaxTime[b]!.compareTo(groupMaxTime[a]!));

  return sortedLabels.map((label) {
    return TimelineGroup(label: label, files: groups[label]!);
  }).toList();
});

/// 按后缀名分组的文件列表
final extensionGroupedFileListProvider = Provider<List<ExtensionGroup>>((ref) {
  final files = ref.watch(filteredFileListProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  final groups = <String, List<FileItem>>{};
  final groupMaxTime = <String, int>{};

  for (final file in files) {
    final ext = file.extension.toUpperCase();
    if (!groups.containsKey(ext)) {
      groups[ext] = [];
      groupMaxTime[ext] = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
    } else {
      final t = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
      if (t > groupMaxTime[ext]!) {
        groupMaxTime[ext] = t;
      }
    }
    groups[ext]!.add(file);
  }

  // 按每组最新文件时间排序（与文件排序方向一致）
  final sortedLabels = groupMaxTime.keys.toList()
    ..sort((a, b) => sortAscending
        ? groupMaxTime[a]!.compareTo(groupMaxTime[b]!)
        : groupMaxTime[b]!.compareTo(groupMaxTime[a]!));

  return sortedLabels.map((ext) {
    return ExtensionGroup(label: ext, files: groups[ext]!);
  }).toList();
});

/// 时间轴 + 后缀嵌套分组（先按时间轴分组，再在每组内按后缀分组）
final nestedGroupedFileListProvider = Provider<List<NestedTimelineGroup>>((ref) {
  final timelineGroups = ref.watch(timelineGroupedFileListProvider);
  final sortAscending = ref.watch(sortAscendingProvider);

  return timelineGroups.map((tg) {
    // 在每个时间轴组内，按后缀分组
    final extGroups = <String, List<FileItem>>{};
    final extMaxTime = <String, int>{};

    for (final file in tg.files) {
      final ext = file.extension.toUpperCase();
      if (!extGroups.containsKey(ext)) {
        extGroups[ext] = [];
        extMaxTime[ext] = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
      } else {
        final t = file.modifiedAt?.millisecondsSinceEpoch ?? 0;
        if (t > extMaxTime[ext]!) {
          extMaxTime[ext] = t;
        }
      }
      extGroups[ext]!.add(file);
    }

    // 按每组最新文件时间排序
    final sortedExts = extMaxTime.keys.toList()
      ..sort((a, b) => sortAscending
          ? extMaxTime[a]!.compareTo(extMaxTime[b]!)
          : extMaxTime[b]!.compareTo(extMaxTime[a]!));

    return NestedTimelineGroup(
      label: tg.label,
      extensionGroups: sortedExts
          .map((ext) => ExtensionGroup(label: ext, files: extGroups[ext]!))
          .toList(),
    );
  }).toList();
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
