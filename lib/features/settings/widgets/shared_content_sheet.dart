import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/permission_utils.dart';
import '../../../shared/widgets/glass_switch.dart';
import '../providers/settings_provider.dart';

/// 手机端共享内容弹窗内容
///
/// 打开时自动检测权限状态，同步开关。
/// 权限提示弹窗和文件夹浏览器通过根 Overlay 渲染，覆盖整个屏幕
/// （包括共享内容弹窗），但不会关闭共享内容弹窗。
class SharedContentMobileBody extends ConsumerStatefulWidget {
  const SharedContentMobileBody({super.key});

  @override
  ConsumerState<SharedContentMobileBody> createState() =>
      _SharedContentMobileBodyState();
}

class _SharedContentMobileBodyState
    extends ConsumerState<SharedContentMobileBody> {
  bool _checking = true;
  OverlayEntry? _folderPickerEntry;
  OverlayEntry? _permissionEntry;

  @override
  void initState() {
    super.initState();
    _syncPermissions();
  }

  @override
  void dispose() {
    _folderPickerEntry?.remove();
    _permissionEntry?.remove();
    super.dispose();
  }

  Future<void> _syncPermissions() async {
    final notifier = ref.read(sharedContentProvider.notifier);
    final settings = ref.read(sharedContentProvider);

    if (settings.album) {
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;
      final storageStatus = await Permission.storage.status;
      // 相册需要图片或视频权限至少一个
      if (!photosStatus.isGranted && !videosStatus.isGranted && !storageStatus.isGranted) {
        notifier.album = false;
      }
    }

    if (settings.music) {
      final audioStatus = await Permission.audio.status;
      final storageStatus = await Permission.storage.status;
      if (!audioStatus.isGranted && !storageStatus.isGranted) {
        notifier.music = false;
      }
    }

    // 文档/下载/文件夹需要 MANAGE_EXTERNAL_STORAGE（Android 11+）
    final hasAllFilesAccess = await PermissionUtils.hasAllFilesAccess();
    if (!hasAllFilesAccess) {
      if (settings.documents) notifier.documents = false;
      if (settings.downloads) notifier.downloads = false;
      if (settings.folderEnabled) notifier.folderEnabled = false;
    }

    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(sharedContentProvider);
    final colors = AppColorScheme.of(context);
    final folderEnabled = settings.folderEnabled;

    if (_checking) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SharedOptionTile(
          icon: Icons.photo_outlined,
          title: AppStrings.sharedAlbum,
          subtitle: AppStrings.sharedAlbumSub,
          value: settings.album,
          onChanged: (v) => _onToggle(_ContentType.album, v),
        ),
        Divider(height: 1, color: colors.divider),
        _SharedOptionTile(
          icon: Icons.music_note_outlined,
          title: AppStrings.sharedMusic,
          subtitle: AppStrings.sharedMusicSub,
          value: settings.music,
          onChanged: (v) => _onToggle(_ContentType.music, v),
        ),
        Divider(height: 1, color: colors.divider),
        _SharedOptionTile(
          icon: Icons.description_outlined,
          title: AppStrings.sharedDocuments,
          subtitle: AppStrings.sharedDocumentsSub,
          value: settings.documents,
          onChanged: (v) => _onToggle(_ContentType.documents, v),
        ),
        Divider(height: 1, color: colors.divider),
        _SharedOptionTile(
          icon: Icons.download_outlined,
          title: AppStrings.sharedDownloads,
          subtitle: AppStrings.sharedDownloadsSub,
          value: settings.downloads,
          onChanged: (v) => _onToggle(_ContentType.downloads, v),
        ),
        Divider(height: 1, color: colors.divider),
        _SharedOptionTile(
          icon: Icons.folder_outlined,
          title: AppStrings.sharedFolder,
          subtitle: AppStrings.sharedFolderSub,
          value: folderEnabled,
          onChanged: (v) async {
            if (v) {
              // 开启文件夹共享前检查所有文件访问权限
              final granted = await PermissionUtils.requestAllFilesAccess();
              if (!granted) {
                if (mounted) _showPermissionDenied();
                return;
              }
            }
            ref.read(sharedContentProvider.notifier).folderEnabled = v;
            if (v && settings.folders.isEmpty) {
              _openFolderPicker();
            }
          },
        ),
        if (folderEnabled) ...[
          const SizedBox(height: 8),
          const _FolderList(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _openFolderPicker,
              icon: const Icon(Icons.add, size: 18),
              label: Text(AppStrings.addFolder),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.inputBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _onToggle(_ContentType type, bool value) async {
    final notifier = ref.read(sharedContentProvider.notifier);

    if (!value) {
      switch (type) {
        case _ContentType.album:
          notifier.album = false;
          break;
        case _ContentType.music:
          notifier.music = false;
          break;
        case _ContentType.documents:
          notifier.documents = false;
          break;
        case _ContentType.downloads:
          notifier.downloads = false;
          break;
        case _ContentType.folder:
          break;
      }
      return;
    }

    switch (type) {
      case _ContentType.album:
        // 相册包含图片和视频，需要同时请求两个权限
        final photosGranted = await _requestMediaPermission(
          Permission.photos,
          Permission.storage,
        );
        // 请求视频权限（Android 13+ 需要 READ_MEDIA_VIDEO）
        final videosGranted = await _requestMediaPermission(
          Permission.videos,
          Permission.storage,
        );
        if (photosGranted || videosGranted) {
          notifier.album = true;
        } else if (mounted) {
          _showPermissionDenied(description: AppStrings.permissionPhotosDesc);
        }
        break;
      case _ContentType.music:
        final granted = await _requestMediaPermission(
          Permission.audio,
          Permission.storage,
        );
        if (granted) {
          notifier.music = true;
        } else if (mounted) {
          _showPermissionDenied(description: AppStrings.permissionStorageDesc);
        }
        break;
      case _ContentType.documents:
        // Android 11+ 访问非媒体文件需要 MANAGE_EXTERNAL_STORAGE
        final docGranted = await PermissionUtils.requestAllFilesAccess();
        if (!docGranted) {
          if (mounted) _showPermissionDenied();
          return;
        }
        notifier.documents = true;
        break;
      case _ContentType.downloads:
        final dlGranted = await PermissionUtils.requestAllFilesAccess();
        if (!dlGranted) {
          if (mounted) _showPermissionDenied();
          return;
        }
        notifier.downloads = true;
        break;
      case _ContentType.folder:
        break;
    }
  }

  /// 通过根 Overlay 插入文件夹选择器，覆盖整个屏幕
  void _openFolderPicker() {
    _folderPickerEntry?.remove();
    _folderPickerEntry = OverlayEntry(
      builder: (_) => _FolderPickerOverlay(
        onClose: () {
          _folderPickerEntry?.remove();
          _folderPickerEntry = null;
        },
        onSelected: (path) {
          ref.read(sharedContentProvider.notifier).addFolder(path);
          _folderPickerEntry?.remove();
          _folderPickerEntry = null;
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_folderPickerEntry!);
  }

  /// 通过根 Overlay 插入权限拒绝提示，覆盖整个屏幕
  void _showPermissionDenied({String? description}) {
    _permissionEntry?.remove();
    _permissionEntry = OverlayEntry(
      builder: (_) => _PermissionDeniedOverlay(
        description: description ?? AppStrings.permissionStorageDesc,
        onClose: () {
          _permissionEntry?.remove();
          _permissionEntry = null;
        },
        onGoToSettings: () {
          _permissionEntry?.remove();
          _permissionEntry = null;
          openAppSettings();
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_permissionEntry!);
  }

  Future<bool> _requestMediaPermission(
    Permission primary,
    Permission fallback,
  ) async {
    final status = await primary.request();
    if (status.isGranted) return true;
    if (status.isDenied) {
      final fallbackStatus = await fallback.request();
      return fallbackStatus.isGranted;
    }
    return false;
  }
}

/// 共享选项 Tile
class _SharedOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SharedOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return ListTile(
      leading: Icon(icon, color: colors.iconSecondary, size: 24),
      title: Text(
        title,
        style: TextStyle(color: colors.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
      trailing: GlassSwitch(value: value, onChanged: onChanged),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

/// 文件夹列表
class _FolderList extends ConsumerWidget {
  const _FolderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sharedContentProvider);
    final colors = AppColorScheme.of(context);

    if (settings.folders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          AppStrings.noFolders,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Column(
      children: settings.folders.map((path) {
        final name = path.split(RegExp(r'[/\\]')).last;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.inputBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.folder, size: 20, color: colors.iconSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      path,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
                onPressed: () {
                  ref.read(sharedContentProvider.notifier).removeFolder(path);
                },
                tooltip: AppStrings.removeFolder,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 内容类型枚举
enum _ContentType { album, music, documents, downloads, folder }

// ---------------------------------------------------------------------------
// Overlay 组件（不关闭共享内容弹窗）
// ---------------------------------------------------------------------------

/// 权限拒绝提示 overlay
class _PermissionDeniedOverlay extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onGoToSettings;
  final String description;

  const _PermissionDeniedOverlay({
    required this.onClose,
    required this.onGoToSettings,
    this.description = AppStrings.permissionStorageDesc,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: colors.iconSecondary),
                const SizedBox(height: 16),
                Text(
                  AppStrings.permissionDeniedTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(AppStrings.close),
                    ),
                    FilledButton(
                      onPressed: onGoToSettings,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(AppStrings.goToSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 文件夹选择器 overlay（全屏覆盖在共享内容弹窗之上）
class _FolderPickerOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onSelected;

  const _FolderPickerOverlay({
    required this.onClose,
    required this.onSelected,
  });

  @override
  State<_FolderPickerOverlay> createState() => _FolderPickerOverlayState();
}

class _FolderPickerOverlayState extends State<_FolderPickerOverlay> {
  late String _currentPath;
  List<FileSystemEntity> _dirs = [];
  bool _loading = true;
  String? _error;

  /// 安全根路径，不允许返回到比这更高的层级
  static const String _rootPath = '/storage/emulated/0';

  @override
  void initState() {
    super.initState();
    _currentPath = _rootPath;
    _loadDirs();
  }

  Future<void> _loadDirs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(_currentPath);
      if (!await dir.exists()) {
        setState(() {
          _error = '路径不存在';
          _loading = false;
        });
        return;
      }
      final entities = await dir.list().toList();
      final dirs = entities
          .whereType<Directory>()
          .where((d) {
            final name = d.path.split(RegExp(r'[/\\]')).last;
            return !name.startsWith('.') && !name.startsWith('_');
          })
          .toList()
        ..sort((a, b) {
          final na = a.path.split(RegExp(r'[/\\]')).last.toLowerCase();
          final nb = b.path.split(RegExp(r'[/\\]')).last.toLowerCase();
          return na.compareTo(nb);
        });
      if (mounted) {
        setState(() {
          _dirs = dirs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '无法访问此目录';
          _loading = false;
        });
      }
    }
  }

  void _enterDir(String path) {
    _currentPath = path;
    _loadDirs();
  }

  void _goParent() {
    if (_currentPath == _rootPath) return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.join('/');
    if (_currentPath.isEmpty) _currentPath = _rootPath;
    // 不允许超出根路径
    if (_currentPath.length < _rootPath.length) {
      _currentPath = _rootPath;
    }
    _loadDirs();
  }

  String _shortName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }

  bool _canGoParent() {
    return _currentPath != _rootPath && _currentPath.length > _rootPath.length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // AppBar
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: colors.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                        color: colors.iconSecondary,
                      ),
                      Expanded(
                        child: Text(
                          AppStrings.selectFolder,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onSelected(_currentPath),
                        child: Text(AppStrings.selectThisFolder),
                      ),
                    ],
                  ),
                ),
                // 路径栏 + 返回上一级
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: colors.cardBg,
                  child: Row(
                    children: [
                      if (_canGoParent())
                        InkWell(
                          onTap: _goParent,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  size: 18,
                                  color: colors.iconPrimary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  AppStrings.parentDir,
                                  style: TextStyle(
                                    color: colors.iconPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentPath,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // 目录列表
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            )
                          : _dirs.isEmpty
                              ? Center(
                                  child: Text(
                                    '此目录下没有子文件夹',
                                    style:
                                        TextStyle(color: colors.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _dirs.length,
                                  itemBuilder: (context, index) {
                                    final dir = _dirs[index];
                                    final name = _shortName(dir.path);
                                    return ListTile(
                                      leading: Icon(
                                        Icons.folder,
                                        color: colors.iconSecondary,
                                      ),
                                      title: Text(
                                        name,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.chevron_right,
                                        color: colors.iconSecondary,
                                        size: 20,
                                      ),
                                      onTap: () => _enterDir(dir.path),
                                    );
                                  },
                                ),
                ),
                // 底部确认按钮
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: colors.divider),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => widget.onSelected(_currentPath),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(
                        '${AppStrings.selectThisFolder}: ${_shortName(_currentPath)}',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
