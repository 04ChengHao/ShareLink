import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/app_image_cache_manager.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/app_toast.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';
import '../services/download_service.dart';
import '../services/media_duration_service.dart';
import '../services/remote_file_service.dart';
import '../views/file_viewer_page.dart';

/// 弹出文件详情（桌面端：右侧抽屉，参考添加分类；移动端：可拖拽底部弹窗）
Future<void> openFileDetails(
  BuildContext context, {
  required FileItem file,
  required String? deviceIp,
  required String? deviceName,
  required String categoryName,
}) async {
  if (PlatformUtils.isDesktop) {
    // 桌面端：右侧抽屉，不使用底部拖动弹窗
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));
        return SlideTransition(position: offset, child: child);
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FileDetailsDesktopDrawer(
          file: file,
          deviceIp: deviceIp,
          deviceName: deviceName,
          categoryName: categoryName,
        );
      },
    );
    return;
  }

  // 移动端：标准底部弹窗（真实 Route），避免 unified_popups 的 Sheet
  // 用 Overlay 承载导致内部 showDialog / Navigator 弹出被遮挡、按钮点击无响应
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) => _MobileDetailsSheet(
      file: file,
      deviceIp: deviceIp,
      deviceName: deviceName,
      categoryName: categoryName,
    ),
  );
}

/// 移动端文件详情底部弹窗外壳
class _MobileDetailsSheet extends StatelessWidget {
  final FileItem file;
  final String? deviceIp;
  final String? deviceName;
  final String categoryName;

  const _MobileDetailsSheet({
    required this.file,
    this.deviceIp,
    this.deviceName,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(color: theme.colorScheme.surface),
          child: Column(
            children: [
              // 顶部拖拽手柄
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 10),
                decoration: BoxDecoration(
                  color: colors.iconSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '文件详情',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Divider(height: 1, color: colors.divider),
              // 内容（复用全部逻辑）
              Expanded(
                child: FileDetailsContent(
                  file: file,
                  deviceIp: deviceIp,
                  deviceName: deviceName,
                  categoryName: categoryName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端文件详情右侧抽屉
class _FileDetailsDesktopDrawer extends StatelessWidget {
  final FileItem file;
  final String? deviceIp;
  final String? deviceName;
  final String categoryName;

  const _FileDetailsDesktopDrawer({
    required this.file,
    this.deviceIp,
    this.deviceName,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          height: screenHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(-4, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 16, 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 24,
                      color: colors.iconPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '文件详情',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      color: colors.iconSecondary,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.divider),
              // 详情内容（复用移动端同一套内容）
              Expanded(
                child: FileDetailsContent(
                  file: file,
                  deviceIp: deviceIp,
                  deviceName: deviceName,
                  categoryName: categoryName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FileDetailsContent extends ConsumerStatefulWidget {
  final FileItem file;
  final String? deviceIp;
  final String? deviceName;
  final String categoryName;

  const FileDetailsContent({
    super.key,
    required this.file,
    this.deviceIp,
    this.deviceName,
    required this.categoryName,
  });

  @override
  ConsumerState<FileDetailsContent> createState() => _FileDetailsContentState();
}

class _FileDetailsContentState extends ConsumerState<FileDetailsContent> {
  String? _downloadPath;
  int? _duration;

  String get _deviceName => widget.deviceName ?? '本机';

  @override
  void initState() {
    super.initState();
    _loadDownloadPath();
    _loadDuration();
  }

  Future<void> _loadDownloadPath() async {
    final p = await DownloadService.instance.getDownloadedPath(
      deviceName: _deviceName,
      fileName: widget.file.name,
      size: widget.file.size,
    );
    final exists = p != null && File(p).existsSync();
    if (mounted) {
      setState(() => _downloadPath = exists ? p : null);
    }
  }

  Future<void> _loadDuration() async {
    final file = widget.file;
    if (!(file.isVideo || file.isAudio)) return;
    // 1) 优先取分享/扫描时已带上的时长
    if (file.duration != null) {
      if (mounted) setState(() => _duration = file.duration);
      return;
    }
    // 2) 只读缓存：有缓存直接显示，不重新扫描文件
    final cached = MediaDurationService.instance.getCachedDuration(
      deviceName: _deviceName,
      fileName: file.name,
      size: file.size,
    );
    if (cached != null) {
      if (mounted) setState(() => _duration = cached);
      return;
    }
    // 3) 无任何信息：首次打开才探测文件时长并写入缓存
    _probeDuration(file);
  }

  Future<void> _probeDuration(FileItem file) async {
    if (!mounted) return;
    final uri = widget.deviceIp != null
        ? RemoteFileService.instance.buildFileUrl(widget.deviceIp!, file.path)
        : 'file://${file.path}';
    final probed = await MediaDurationService.instance.getDuration(
      deviceName: _deviceName,
      fileName: file.name,
      size: file.size,
      uri: uri,
    );
    if (mounted) {
      setState(() => _duration = probed);
    }
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '--';
    final totalSec = (ms / 1000).round();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// 持久下载到下载目录（带进度弹窗），用于"下载"按钮
  Future<void> _download() async {
    if (widget.deviceIp == null) return;
    // 手机端确保已获得"所有文件访问"权限，否则中止（避免落到应用私有 data 目录）
    if (!await DownloadService.instance.ensureMobileDownloadPermission()) {
      if (mounted) {
        showAppToast(context, '未获得"所有文件访问"权限，无法保存到系统下载目录', type: ToastType.warning);
      }
      return;
    }
    final key = widget.file.uniqueKey;
    final notifier = ref.read(downloadProgressProvider.notifier);
    notifier.start(key);

    final path = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PerformProgressDialog(
        loadingText: '正在下载到下载目录',
        completedText: '下载完成',
        perform: ({required onProgress, required onCancel}) =>
            DownloadService.instance.download(
          deviceIp: widget.deviceIp!,
          deviceName: _deviceName,
          categoryName: widget.categoryName,
          file: widget.file,
          onProgress: onProgress,
          onCancel: onCancel,
        ),
      ),
    );

    notifier.end(key);
    if (!mounted) return;
    if (path != null) {
      setState(() => _downloadPath = path);
      showAppToast(context, '已下载到下载目录', type: ToastType.success);
    }
  }

  /// 是否为本地"下载文件"（位于 Download 目录下，视为从其他设备下载而来）
  ///
  /// 仅用于本机浏览时在底部展示"删除"入口。
  bool get _isLocalDownloaded =>
      widget.deviceIp == null &&
      RegExp(
        r'[/\\]Download[/\\]',
        caseSensitive: false,
      ).hasMatch(widget.file.path);

  /// 删除下载文件（带确认提示框）
  ///
  /// - 远程文件：删除已下载到本地的副本（Download/ShareLink）
  /// - 本机下载文件（位于 Download 目录下）：删除该本地文件本身
  Future<void> _deleteCurrent() async {
    final path = _isLocalDownloaded ? widget.file.path : _downloadPath;
    if (path == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DeleteConfirmDialog(
        fileName: widget.file.name,
        isLocal: _isLocalDownloaded,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (File(path).existsSync()) {
        final dir = File(path).parent;
        File(path).deleteSync();
        // 目录为空则一并清除（保持下载目录整洁）
        if (dir.existsSync() && dir.listSync().isEmpty) {
          dir.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[FileDetails] 删除下载文件失败: $e');
    }
    if (!_isLocalDownloaded) {
      DownloadService.instance.removeDownloaded(
        deviceName: _deviceName,
        fileName: widget.file.name,
        size: widget.file.size,
      );
    }
    if (mounted) {
      showAppToast(context, '已删除下载文件', type: ToastType.success);
    }
    // 关闭详情弹窗
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    // 自增下载版本号：让"仅下载文件"过滤链重新计算（本地/远程统一刷新列表）
    ref.read(downloadedStampProvider.notifier).bump();
    // 本机：再从内存缓存移除该物理文件并基于缓存重新发射，避免全量重扫
    if (widget.deviceIp == null) {
      ref.read(localFileServiceProvider).removeFileFromCache(path);
      ref.read(fileListProvider.notifier).scanFiles(null, checkReady: true);
    }
  }

  /// 系统打开：优先复用下载缓存；未命中走临时缓存路线（带进度弹窗），不自动持久下载
  Future<void> _openWithSystem() async {
    final remoteService = RemoteFileService.instance;
    final localService = ref.read(localFileServiceProvider);

    String path;
    if (widget.deviceIp != null) {
      final cached = await DownloadService.instance.findCachedFile(
        deviceName: _deviceName,
        fileName: widget.file.name,
        size: widget.file.size,
      );
      if (cached != null) {
        path = cached;
      } else {
        // 与预览页一致：显示带进度条/取消按钮的下载弹窗
        final temp = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PerformProgressDialog(
            loadingText: '正在下载远程文件到本地',
            completedText: '正在打开…',
            perform: ({required onProgress, required onCancel}) =>
                remoteService.downloadToTemp(
              widget.deviceIp!,
              widget.file.path,
              onProgress: onProgress,
              onCancel: onCancel,
            ),
          ),
        );
        if (temp == null) {
          if (mounted) {
            showAppToast(context, '文件加载失败', type: ToastType.error);
          }
          return;
        }
        path = temp;
      }
    } else {
      path = widget.file.path;
    }

    final ok = await localService.openFile(path);
    if (!ok && mounted) {
      showAppToast(context, '无法打开文件：${widget.file.name}', type: ToastType.error);
    }
  }

  void _preview() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FileViewerPage(
          file: widget.file,
          remoteDeviceIp: widget.deviceIp,
        ),
      ),
    );
  }

  /// 在系统文件管理器中定位文件（移动端打开所在文件夹，桌面定位文件）
  void _revealAt(String path) {
    if (PlatformUtils.isMobile) {
      PlatformUtils.openFolder(File(path).parent.path);
    } else {
      PlatformUtils.openInSystem(path);
    }
  }

  /// 复制路径到剪贴板并提示
  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      // 用根 Overlay Toast，避免被详情弹窗（底部弹窗/抽屉）的 modal barrier 遮挡
      showAppToast(context, '已复制路径');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final file = widget.file;

    // 底部中间的下载/删除按钮是否出现及形态
    // - 远程：总是显示（未下载→下载，已下载→删除）
    // - 本机：仅"下载文件"显示删除
    final hasDownloadAction = widget.deviceIp != null || _isLocalDownloaded;
    final showDeleteAction = _isLocalDownloaded || _downloadPath != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 封面
                  Center(
                    child: _buildCover(colors, 160),
                  ),
                  const SizedBox(height: 20),
                  // 字段
                  _infoRow('文件名', file.name),
                  // 本地文件：文件地址可点击跳转（打开所在文件夹 / 资源管理器定位文件）
                  _infoRow(
                    '文件地址',
                    file.path,
                    onTap: widget.deviceIp == null
                        ? () => _revealAt(file.path)
                        : null,
                    onLongPress: () => _copyPath(file.path),
                  ),
                  // 远程文件才显示"下载状态"行（本机无下载概念）；下载/删除按钮
                  // 统一放在底部"预览/打开"中间，见底部按钮区
                  if (widget.deviceIp != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              '下载状态',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _downloadPath != null ? '已下载' : '未下载',
                              style: TextStyle(
                                fontSize: 13,
                                color: _downloadPath != null
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_downloadPath != null) ...[
                    _infoRow(
                      '下载地址',
                      _downloadPath!,
                      onTap: () {
                        // 移动端打开文件所在文件夹；桌面端资源管理器定位到文件
                        if (PlatformUtils.isMobile) {
                          PlatformUtils.openFolder(File(_downloadPath!).parent.path);
                        } else {
                          PlatformUtils.openInSystem(_downloadPath!);
                        }
                      },
                      onLongPress: () => _copyPath(_downloadPath!),
                    ),
                  ],
                  _infoRow('文件大小', file.formattedSize),
                  _infoRow('修改时间', file.formattedDate),
                  _infoRow('文件类型', file.extension.isNotEmpty ? file.extension : '未知'),
                  if (file.isVideo || file.isAudio)
                    _infoRow(
                      file.isVideo ? '视频时长' : '音频时长',
                      _formatDuration(_duration),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 底部按钮：预览 | 下载/删除 | 打开
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  label: const Text('预览'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    side: BorderSide(color: colors.inputBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 下载/删除按钮（绿色/红色），与预览、打开等宽、间距均匀
              if (hasDownloadAction) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: showDeleteAction ? _deleteCurrent : _download,
                    icon: Icon(
                      showDeleteAction
                          ? Icons.delete_outline
                          : Icons.download_outlined,
                      size: 20,
                    ),
                    label: Text(showDeleteAction ? '删除' : '下载'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          showDeleteAction ? Colors.red : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openWithSystem,
                  icon: const Icon(Icons.open_in_new, size: 20),
                  label: const Text('打开'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCover(AppColorScheme colors, double coverSize) {
    final file = widget.file;
    Widget child;

    if (file.isImage && widget.deviceIp != null) {
      // 远程：复用 CachedNetworkImage 磁盘缓存，避免重复下载导致空白
      child = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: coverSize,
          height: coverSize,
          child: CachedNetworkImage(
            imageUrl: RemoteFileService.instance.buildFileUrl(
              widget.deviceIp!,
              file.path,
            ),
            cacheManager: AppImageCacheManager.instance,
            fit: BoxFit.cover,
            memCacheWidth: 600,
            placeholder: (_, _) => _coverPlaceholder(colors),
            errorWidget: (_, _, _) => _coverPlaceholder(colors),
          ),
        ),
      );
    } else if (file.isImage) {
      // 本机：与列表项一致的缓存键（ResizeImage + FileImage），命中内存缓存
      child = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: coverSize,
          height: coverSize,
          child: Image(
            image: ResizeImage(FileImage(File(file.path)), width: 400),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _coverPlaceholder(colors),
          ),
        ),
      );
    } else if (file.isVideo) {
      child = _VideoDetailCover(
        videoPath: file.path,
        deviceIp: widget.deviceIp,
        coverSize: coverSize,
        typeColor: file.typeColor,
      );
    } else {
      child = Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.inputBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(file.typeIcon, size: 48, color: file.typeColor),
      );
    }

    return SizedBox(
      width: coverSize,
      height: coverSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          if (file.isVideo)
            Icon(
              Icons.play_circle_fill_rounded,
              size: 40,
              color: Colors.white.withValues(alpha: 0.85),
            ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder(AppColorScheme colors) {
    return Container(
      color: colors.inputBg,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image, color: colors.textHint),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final colors = AppColorScheme.of(context);
    final isClickable = onTap != null || onLongPress != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              // 桌面端鼠标右键也触发复制
              onSecondaryTap: onLongPress,
              onSecondaryTapDown: (_) {},
              child: Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: valueColor ??
                      (isClickable
                          ? colors.iconActive
                          : colors.textPrimary),
                  fontWeight: isClickable ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 视频详情封面（远程缩略图 / 本地缩略图）
class _VideoDetailCover extends ConsumerStatefulWidget {
  final String videoPath;
  final String? deviceIp;
  final double coverSize;
  final Color typeColor;

  const _VideoDetailCover({
    required this.videoPath,
    this.deviceIp,
    required this.coverSize,
    required this.typeColor,
  });

  @override
  ConsumerState<_VideoDetailCover> createState() => _VideoDetailCoverState();
}

class _VideoDetailCoverState extends ConsumerState<_VideoDetailCover> {
  String? _thumb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.deviceIp != null) {
      setState(() {
        _thumb = RemoteFileService.instance.buildThumbnailUrl(
          widget.deviceIp!,
          widget.videoPath,
        );
      });
    } else {
      _gen();
    }
  }

  Future<void> _gen() async {
    final t = await ref
        .read(localFileServiceProvider)
        .getVideoThumbnail(widget.videoPath);
    if (mounted) {
      setState(() {
        _thumb = t;
        _failed = t == null;
      });
    }
  }

  Widget _thumbPlaceholder(AppColorScheme colors) {
    return Container(
      color: colors.inputBg,
      alignment: Alignment.center,
      child: Icon(Icons.video_file, size: 48, color: widget.typeColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    if (_thumb == null || _failed) {
      return Container(
        width: widget.coverSize,
        height: widget.coverSize,
        color: colors.inputBg,
        alignment: Alignment.center,
        child: Icon(Icons.video_file, size: 48, color: widget.typeColor),
      );
    }
    final isRemote = widget.deviceIp != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: widget.coverSize,
        height: widget.coverSize,
        child: isRemote
            ? CachedNetworkImage(
                imageUrl: _thumb!,
                cacheManager: AppImageCacheManager.instance,
                fit: BoxFit.cover,
                memCacheWidth: 600,
                placeholder: (_, _) => _thumbPlaceholder(colors),
                errorWidget: (_, _, _) => _thumbPlaceholder(colors),
              )
            : Image.file(
                File(_thumb!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: colors.inputBg,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.video_file,
                    size: 48,
                    color: widget.typeColor,
                  ),
                ),
              ),
      ),
    );
  }
}

/// 删除下载文件确认弹窗
///
/// 按钮样式与首页"设备断开/取消连接"弹窗（showConfirmDialog）保持一致：
/// 圆形图标 + 标题 + 居中说明 + 「取消（描边）/ 删除（填充）」按钮行。
/// 确认按钮用红色表现删除的破坏性语义。
class _DeleteConfirmDialog extends StatelessWidget {
  final String fileName;
  final bool isLocal;

  const _DeleteConfirmDialog({
    required this.fileName,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  size: 28,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              // 标题
              Text(
                '删除下载文件',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              // 内容
              Text(
                '确定删除「$fileName」${isLocal ? '' : '的本地下载文件'}吗？',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              // 按钮行
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用下载进度弹窗（持久下载 / 临时下载共用）
///
/// [perform] 执行实际的下载逻辑，回调 [onProgress]（0.0~1.0）更新进度，
/// [onCancel] 返回 true 时中止。下载完成后弹窗关闭并携带下载路径。
class _PerformProgressDialog extends ConsumerStatefulWidget {
  final String loadingText;
  final String completedText;
  final Future<String?> Function({
    required void Function(double) onProgress,
    required bool Function() onCancel,
  }) perform;

  const _PerformProgressDialog({
    required this.loadingText,
    required this.completedText,
    required this.perform,
  });

  @override
  ConsumerState<_PerformProgressDialog> createState() =>
      _PerformProgressDialogState();
}

class _PerformProgressDialogState extends ConsumerState<_PerformProgressDialog> {
  double _progress = 0.0;
  bool _completed = false;
  bool _canceled = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final path = await widget.perform(
      onProgress: (p) {
        if (mounted && !_canceled) setState(() => _progress = p);
      },
      onCancel: () => _canceled,
    );

    if (_canceled) return;
    if (mounted) {
      setState(() => _completed = true);
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) Navigator.of(context).pop(path);
    }
  }

  void _cancel() {
    setState(() => _canceled = true);
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 4,
                      color: theme
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.12),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: _completed ? 1.0 : (_progress > 0 ? _progress : null),
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    _progress > 0 ? '${(_progress * 100).toInt()}%' : '...',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _completed ? widget.completedText : widget.loadingText,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _completed ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
        actions: const [],
      ),
    );
  }
}
