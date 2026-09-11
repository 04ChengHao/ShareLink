import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/global_providers.dart';
import '../../../core/services/storage_service.dart';
import '../../file_browser/services/remote_file_service.dart';

// ---------------------------------------------------------------------------
// 共享内容设置（统一模型 + 持久化）
// ---------------------------------------------------------------------------

/// 共享内容设置
class SharedContentSettings {
  /// 相册（含相册和相机的所有图片）
  final bool album;

  /// 音乐
  final bool music;

  /// 文档
  final bool documents;

  /// 下载
  final bool downloads;

  /// 共享文件夹路径列表
  final List<String> folders;

  /// 文件夹共享开关
  final bool folderEnabled;

  const SharedContentSettings({
    this.album = false,
    this.music = false,
    this.documents = false,
    this.downloads = false,
    this.folders = const [],
    this.folderEnabled = false,
  });

  SharedContentSettings copyWith({
    bool? album,
    bool? music,
    bool? documents,
    bool? downloads,
    List<String>? folders,
    bool? folderEnabled,
  }) {
    return SharedContentSettings(
      album: album ?? this.album,
      music: music ?? this.music,
      documents: documents ?? this.documents,
      downloads: downloads ?? this.downloads,
      folders: folders ?? this.folders,
      folderEnabled: folderEnabled ?? this.folderEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'album': album,
    'music': music,
    'documents': documents,
    'downloads': downloads,
    'folders': folders,
    'folderEnabled': folderEnabled,
  };

  factory SharedContentSettings.fromJson(Map<String, dynamic> json) {
    return SharedContentSettings(
      album: json['album'] as bool? ?? false,
      music: json['music'] as bool? ?? false,
      documents: json['documents'] as bool? ?? false,
      downloads: json['downloads'] as bool? ?? false,
      folders: (json['folders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
          const [],
      folderEnabled: json['folderEnabled'] as bool? ?? false,
    );
  }
}

/// 共享内容设置 Provider（持久化，JSON 字符串存储）
final sharedContentProvider =
    NotifierProvider<SharedContentNotifier, SharedContentSettings>(
      SharedContentNotifier.new,
    );

class SharedContentNotifier extends Notifier<SharedContentSettings> {
  @override
  SharedContentSettings build() {
    final prefs = ref.read(sharedPrefsProvider);

    // 优先读取新的统一 JSON 格式
    final jsonStr = prefs.getString(StorageKeys.sharedContent);
    if (jsonStr != null) {
      try {
        return SharedContentSettings.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[SharedContent] 解析 JSON 失败，回退到旧格式: $e');
      }
    }

    // 兼容旧格式（布尔值 sharedAlbum / sharedFolder）
    final oldAlbum = prefs.getBool(StorageKeys.sharedAlbum) ?? false;
    final oldFolder = prefs.getBool(StorageKeys.sharedFolder) ?? false;
    final settings = SharedContentSettings(album: oldAlbum);
    // 如果旧格式中 sharedFolder=true，保留一个空文件夹列表标记
    // (具体路径旧格式未存储，所以不迁移路径)
    debugPrint('[SharedContent] 从旧格式迁移: album=$oldAlbum, folder=$oldFolder');
    return settings;
  }

  void _persist() {
    ref
        .read(sharedPrefsProvider)
        .setString(StorageKeys.sharedContent, jsonEncode(state.toJson()));
  }

  set album(bool value) {
    state = state.copyWith(album: value);
    _persist();
  }

  set music(bool value) {
    state = state.copyWith(music: value);
    _persist();
  }

  set documents(bool value) {
    state = state.copyWith(documents: value);
    _persist();
  }

  set downloads(bool value) {
    state = state.copyWith(downloads: value);
    _persist();
  }

  /// 文件夹开关：独立控制，关闭时不清空文件夹列表
  set folderEnabled(bool value) {
    state = state.copyWith(folderEnabled: value);
    _persist();
  }

  /// 文件夹开关是否开启
  bool get folderEnabled => state.folderEnabled;

  /// 添加共享文件夹（自动开启文件夹共享开关）
  void addFolder(String path) {
    if (state.folders.contains(path)) return;
    state = state.copyWith(
      folders: [...state.folders, path],
      folderEnabled: true,
    );
    _persist();
  }

  /// 移除共享文件夹
  void removeFolder(String path) {
    state = state.copyWith(
      folders: state.folders.where((f) => f != path).toList(),
    );
    _persist();
  }
}

// ---------------------------------------------------------------------------
// 旧 Provider（向后兼容，仅用于其他模块可能引用的过渡期）
// ---------------------------------------------------------------------------

/// 共享相册（旧，向后兼容）
final sharedAlbumProvider = NotifierProvider<SharedAlbumNotifier, bool>(
  SharedAlbumNotifier.new,
);

class SharedAlbumNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedContentProvider).album;
  }

  set enabled(bool value) {
    ref.read(sharedContentProvider.notifier).album = value;
  }
}

/// 共享文件夹（旧，向后兼容）
final sharedFolderProvider = NotifierProvider<SharedFolderNotifier, bool>(
  SharedFolderNotifier.new,
);

class SharedFolderNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedContentProvider).folders.isNotEmpty;
  }

  set enabled(bool value) {
    ref.read(sharedContentProvider.notifier).folderEnabled = value;
  }
}

// ---------------------------------------------------------------------------
// 设置页当前子标签
// ---------------------------------------------------------------------------

/// 设置页当前子标签
final settingsTabProvider = NotifierProvider<SettingsTabNotifier, String>(
  SettingsTabNotifier.new,
);

class SettingsTabNotifier extends Notifier<String> {
  @override
  String build() => 'general';

  set tab(String value) => state = value;
}

// ---------------------------------------------------------------------------
// 缓存大小（实时统计）
// ---------------------------------------------------------------------------

/// 应用缓存总大小（字节）
///
/// 缓存写入/清除后大小变化，而设置页位于 IndexedStack 中保持存活，
/// `initState` 仅在首次进入时执行——依赖本 provider 在以下时机刷新：
/// - 手动点击「刷新」按钮
/// - 每次进入设置页（由外壳导航触发）
/// - 文件扫描完成（索引/缩略图写盘后可能变化）
final cacheSizeProvider = NotifierProvider<CacheSizeNotifier, int>(
  CacheSizeNotifier.new,
);

class CacheSizeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 重新扫描缓存目录并更新大小
  Future<void> refresh() async {
    final size = await RemoteFileService.instance.getTempCacheSize();
    if (size != state) state = size;
  }
}
