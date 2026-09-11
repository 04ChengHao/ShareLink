import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/app_toast.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';
import '../services/download_service.dart';
import '../services/media_duration_service.dart';
import '../services/remote_file_service.dart';
import '../widgets/audio_viewer.dart';
import '../widgets/image_viewer.dart';
import '../widgets/video_viewer.dart';

/// 文件预览页面（二级页面）
///
/// 顶部：返回按钮、文件名标题、系统打开按钮
/// 内容区：根据文件类型显示不同的预览器
/// - 图片：[ImageViewer]（支持鼠标位置缩放、悬浮控制栏、透明网格背景）
/// - 视频：[VideoViewer]（基于 media_kit，全平台支持，含手势控制和全屏）
/// - 音频：[AudioViewer]（基于 media_kit）
/// - 文本：直接显示文件内容
/// - 不支持的格式：显示封面图标 + 提示信息
class FileViewerPage extends ConsumerStatefulWidget {
  final FileItem file;
  final String? remoteDeviceIp;

  const FileViewerPage({
    super.key,
    required this.file,
    this.remoteDeviceIp,
  });

  @override
  ConsumerState<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends ConsumerState<FileViewerPage> {
  /// 是否正在解析远程文件本地缓存（下载文件夹命中）
  bool _resolving = true;

  /// 远程文件本地缓存的绝对路径（未命中为 null）
  String? _localCachePath;

  String get _deviceName =>
      ref.read(effectiveSelectedDeviceProvider) ?? '本机';

  @override
  void initState() {
    super.initState();
    _resolveLocalCache();
  }

  /// 查询该文件是否已有本地下载缓存（供预览/打开复用，不触发下载）
  Future<void> _resolveLocalCache() async {
    if (widget.remoteDeviceIp == null) {
      // 本机：ts 分片合并视频需先拼合成可播放文件
      if (widget.file.isMergedTs) {
        final mergedPath = await ref
            .read(localFileServiceProvider)
            .resolvePlayablePath(widget.file);
        if (!mounted) return;
        if (mergedPath == null) {
          // 分片缺失/读取失败：不能把 null 交给播放器，提示后退出预览
          setState(() => _resolving = false);
          showAppToast(context, AppStrings.tsMergeFailed, type: ToastType.error);
          Navigator.of(context).pop();
          return;
        }
        setState(() {
          _localCachePath = mergedPath;
          _resolving = false;
        });
        return;
      }
      // 本机普通文件无需解析，首帧后关闭 loading（避免 initState 中同步 setState）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _resolving = false);
      });
      return;
    }
    final p = await DownloadService.instance.findCachedFile(
      deviceName: _deviceName,
      fileName: widget.file.name,
      size: widget.file.size,
    );
    if (mounted) {
      setState(() {
        _localCachePath = (p != null && File(p).existsSync()) ? p : null;
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;

    // 解析本地缓存（远程文件 / 本机 ts 合并视频）时先显示 loading，避免画面/播放闪断
    if ((widget.remoteDeviceIp != null || widget.file.isMergedTs) && _resolving) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 视频文件单独走全屏路由（不使用 Scaffold AppBar）
    if (file.isVideo) {
      return _VideoPageWrapper(
        file: file,
        remoteDeviceIp: widget.remoteDeviceIp,
        localPath: _localCachePath,
        deviceName: _deviceName,
      );
    }

    // 图片文件也走全屏沉浸预览（不使用 Scaffold AppBar）
    if (file.isImage) {
      return ImageViewer(
        imagePath: _localCachePath ?? file.path,
        remoteDeviceIp: _localCachePath != null ? null : widget.remoteDeviceIp,
        onBack: () => Navigator.of(context).pop(),
        onOpenWithSystem: () => _openWithSystem(context, ref),
      );
    }

    final colors = AppColorScheme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: AppStrings.openWithSystem,
            onPressed: () => _openWithSystem(context, ref),
          ),
        ],
      ),
      body: _buildContentView(colors),
    );
  }

  /// 根据文件类型构建内容视图
  Widget _buildContentView(AppColorScheme colors) {
    final file = widget.file;

    if (file.isImage) {
      return ImageViewer(
        imagePath: _localCachePath ?? file.path,
        remoteDeviceIp: _localCachePath != null ? null : widget.remoteDeviceIp,
      );
    }
    if (file.isAudio) {
      final local = _localCachePath;
      // 本地路径统一用 Uri.file 构造（Windows 下 'file://C:\...' 不是合法 URI）
      final mediaUri = local != null
          ? Uri.file(local).toString()
          : widget.remoteDeviceIp != null
              ? RemoteFileService.instance.buildFileUrl(
                  widget.remoteDeviceIp!,
                  file.path,
                )
              : Uri.file(file.path).toString();
      return AudioViewer(
        mediaUri: mediaUri,
        title: file.name,
        onDurationKnown: (d) {
          MediaDurationService.instance.cacheDuration(
            deviceName: _deviceName,
            fileName: file.name,
            size: file.size,
            durationMs: d.inMilliseconds,
          );
        },
      );
    }
    if (file.isText || file.isCode) {
      return _TextViewer(
        file: file,
        remoteDeviceIp: widget.remoteDeviceIp,
      );
    }

    // 不支持的文件格式
    return _UnsupportedViewer(file: file);
  }

  /// 使用系统应用打开文件
  ///
  /// 命中本地下载缓存时直接使用本地文件；未命中远程文件经过临时缓存下载后打开。
  Future<void> _openWithSystem(BuildContext context, WidgetRef ref) async {
    final file = widget.file;
    final isRemote = widget.remoteDeviceIp != null;

    String filePath;

    if (isRemote) {
      // 优先复用已下载缓存（不触发下载），未命中再走临时缓存路线
      final cached = await DownloadService.instance.findCachedFile(
        deviceName: _deviceName,
        fileName: file.name,
        size: file.size,
      );
      if (cached != null) {
        filePath = cached;
      } else {
        final remoteService = ref.read(remoteFileServiceProvider);
        final tempPath = await _downloadWithProgressDialog(
          context,
          remoteService,
          widget.remoteDeviceIp!,
          file.path,
        );

        if (tempPath == null) {
          // 用户取消或下载失败
          if (context.mounted) {
            showAppToast(context, AppStrings.fileLoadFailed, type: ToastType.error);
          }
          return;
        }
        filePath = tempPath;
      }
    } else {
      filePath = file.path;
    }

    // 使用 LocalFileService 统一调用系统打开
    final service = ref.read(localFileServiceProvider);
    final success = await service.openFile(filePath);
    if (!success && context.mounted) {
      showAppToast(context, '无法打开文件：${file.name}', type: ToastType.error);
    }
  }

  /// 显示带进度条和取消按钮的下载弹窗
  ///
  /// 用户可点击取消按钮中止下载。
  Future<String?> _downloadWithProgressDialog(
    BuildContext context,
    RemoteFileService remoteService,
    String deviceIp,
    String filePath,
  ) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DownloadProgressDialog(
          remoteService: remoteService,
          deviceIp: deviceIp,
          filePath: filePath,
        );
      },
    );
  }
}

/// 视频页面包装器
///
/// 视频预览支持全屏模式切换。当切换到全屏时，隐藏 AppBar 并强制横屏；
/// 退出全屏时恢复竖屏。
class _VideoPageWrapper extends StatefulWidget {
  final FileItem file;
  final String? remoteDeviceIp;

  /// 已下载的本地缓存路径（命中时直接用本地文件播放/打开）
  final String? localPath;
  final String? deviceName;

  const _VideoPageWrapper({
    required this.file,
    this.remoteDeviceIp,
    this.localPath,
    this.deviceName,
  });

  @override
  State<_VideoPageWrapper> createState() => _VideoPageWrapperState();
}

class _VideoPageWrapperState extends State<_VideoPageWrapper> {
  int? _videoDuration;
  int? _cachedVideoDuration() {
    final dn = widget.deviceName;
    if (dn == null) return null;
    return MediaDurationService.instance.getCachedDuration(
      deviceName: dn,
      fileName: widget.file.name,
      size: widget.file.size,
    );
  }
  int? _resolvedKnownMs() => _videoDuration ?? _cachedVideoDuration();

  @override
  void initState() {
    super.initState();
    _ensureDuration();
  }

  Future<void> _ensureDuration() async {
    // 已有缓存直接返回，不重复探测
    if (_cachedVideoDuration() != null) return;
    final dn = widget.deviceName ?? "本机";
    final file = widget.file;
    final uri = widget.localPath != null
        ? Uri.file(widget.localPath!).toString()
        : widget.remoteDeviceIp != null
            ? RemoteFileService.instance.buildFileUrl(
                widget.remoteDeviceIp!, file.path,
              )
            : Uri.file(file.path).toString();
    final d = await MediaDurationService.instance.getDuration(
      deviceName: dn,
      fileName: file.name,
      size: file.size,
      uri: uri,
    );
    if (mounted) setState(() => _videoDuration = d);
  }
  bool _isFullscreen = false;

  @override
  void dispose() {
    // 退出时恢复竖屏
    if (PlatformUtils.isMobile) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (PlatformUtils.isMobile) {
      if (_isFullscreen) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      }
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  void _onBack() {
    if (_isFullscreen) {
      _toggleFullscreen();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final local = widget.localPath;
    // 本地路径统一用 Uri.file 构造（Windows 下 'file://C:\...' 不是合法 URI）
    final mediaUri = local != null
        ? Uri.file(local).toString()
        : widget.remoteDeviceIp != null
            ? RemoteFileService.instance.buildFileUrl(
                widget.remoteDeviceIp!,
                file.path,
              )
            : Uri.file(file.path).toString();

    if (_isFullscreen) {
      // 全屏模式：仅显示视频，无 AppBar
      return Scaffold(
        backgroundColor: Colors.black,
        body: VideoViewer(
          mediaUri: mediaUri,
          title: file.name,
          isFullscreen: true,
          onToggleFullscreen: _toggleFullscreen,
          onBack: _onBack,
          knownDurationMs: _resolvedKnownMs(),
          onDurationKnown: (d) {
            final dn = widget.deviceName;
            if (dn == null) return;
            MediaDurationService.instance.cacheDuration(
              deviceName: dn,
              fileName: widget.file.name,
              size: widget.file.size,
              durationMs: d.inMilliseconds,
            );
          },
        ),
      );
    }

    // 非全屏模式：带 AppBar 的页面
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _onBack,
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            tooltip: AppStrings.openWithSystem,
            onPressed: () => _openWithSystemForVideo(context),
          ),
        ],
      ),
      body: VideoViewer(
        mediaUri: mediaUri,
        title: file.name,
        isFullscreen: false,
        knownDurationMs: _resolvedKnownMs(),
        onToggleFullscreen: _toggleFullscreen,
        onDurationKnown: (d) {
          final dn = widget.deviceName;
          if (dn == null) return;
          MediaDurationService.instance.cacheDuration(
            deviceName: dn,
            fileName: widget.file.name,
            size: widget.file.size,
            durationMs: d.inMilliseconds,
          );
        },
      ),
    );
  }

  Future<void> _openWithSystemForVideo(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final remoteService = container.read(remoteFileServiceProvider);
    final localService = container.read(localFileServiceProvider);
    final file = widget.file;

    String filePath;
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      filePath = widget.localPath!;
    } else if (widget.remoteDeviceIp != null) {
      // 优先复用已下载缓存，未命中走临时缓存路线
      final deviceName =
          container.read(effectiveSelectedDeviceProvider) ?? '本机';
      final cached = await DownloadService.instance.findCachedFile(
        deviceName: deviceName,
        fileName: file.name,
        size: file.size,
      );
      if (cached != null) {
        filePath = cached;
      } else {
        final tempPath = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _DownloadProgressDialog(
              remoteService: remoteService,
              deviceIp: widget.remoteDeviceIp!,
              filePath: file.path,
            );
          },
        );
        if (tempPath == null) {
          if (context.mounted) {
            showAppToast(context, AppStrings.fileLoadFailed, type: ToastType.error);
          }
          return;
        }
        filePath = tempPath;
      }
    } else {
      filePath = file.path;
    }

    final success = await localService.openFile(filePath);
    if (!success && context.mounted) {
      showAppToast(context, '无法打开文件：${file.name}', type: ToastType.error);
    }
  }
}

/// 下载进度弹窗
///
/// 显示圆形加载进度条（含百分比）和取消按钮。
/// 用户可点击取消按钮中止下载。
///
/// 通过 [RemoteFileService.downloadToTemp] 的 `onProgress` 回调接收实时进度，
/// 通过 `onCancel` 回调检查是否已取消，立即中止下载。
class _DownloadProgressDialog extends StatefulWidget {
  final RemoteFileService remoteService;
  final String deviceIp;
  final String filePath;

  const _DownloadProgressDialog({
    required this.remoteService,
    required this.deviceIp,
    required this.filePath,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  bool _completed = false;
  bool _canceled = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final result = await widget.remoteService.downloadToTemp(
        widget.deviceIp,
        widget.filePath,
        onProgress: (progress) {
          if (mounted && !_canceled) {
            setState(() => _progress = progress);
          }
        },
        onCancel: () => _canceled,
      );

      if (_canceled) return;

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _completed = true;
        });
        // 短暂延迟后关闭弹窗
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted && !_canceled) {
          Navigator.of(context).pop(result);
        }
      }
    } catch (_) {
      if (mounted && !_canceled) {
        Navigator.of(context).pop(null);
      }
    }
  }

  void _cancel() {
    setState(() => _canceled = true);
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
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
            // 圆形进度条
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 背景轨迹
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 4,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.12),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: _completed
                          ? 1.0
                          : (_progress > 0 ? _progress : null),
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    _progress > 0
                        ? '${(_progress * 100).toInt()}%'
                        : '...',
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
              _completed ? '正在打开…' : AppStrings.fileLoading,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '正在下载远程文件到本地',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
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

// =============================================================================
// 文本预览器
// =============================================================================

/// 文本预览器
///
/// 采用分块流式读取，避免大文件一次性加载导致卡死或内存溢出。
/// - 本机文件：先预检文件大小，超过 2MB 直接提示用系统软件打开；
///   使用 `openRead` 分块读取，限制最大预览 512KB
/// - 远程文件：通过 HTTP 流式分块接收，限制最大预览 512KB
///
/// 超过限制时在末尾显示截断提示。
class _TextViewer extends StatefulWidget {
  final FileItem file;
  final String? remoteDeviceIp;

  const _TextViewer({required this.file, this.remoteDeviceIp});

  @override
  State<_TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<_TextViewer> {
  /// 最大预览字节数（512KB），防止内存溢出导致应用卡死
  static const int _maxPreviewBytes = 512 * 1024;

  /// 超过此大小（2MB）的文件不尝试预览，直接提示用系统软件打开
  static const int _maxFileBytes = 2 * 1024 * 1024;

  String? _content;
  bool _loading = true;
  bool _failed = false;
  bool _truncated = false;
  bool _tooLarge = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      // 预检本机文件大小，超大文件不加载
      if (widget.remoteDeviceIp == null) {
        final fileSize = await File(widget.file.path).length();
        if (fileSize > _maxFileBytes) {
          if (mounted) {
            setState(() {
              _tooLarge = true;
              _loading = false;
            });
          }
          return;
        }
      }

      final buffer = <int>[];
      bool truncated = false;

      if (widget.remoteDeviceIp != null) {
        // 远程文件：fetchTextContent 已限制大小
        final text = await RemoteFileService.instance.fetchTextContent(
          widget.remoteDeviceIp!,
          widget.file.path,
        );
        if (text == null) {
          if (mounted) setState(() => _failed = true);
          return;
        }
        final bytes = utf8.encode(text);
        truncated = bytes.length >= _maxPreviewBytes;
        buffer.addAll(bytes);
      } else {
        // 本机文件：分块流式读取，避免大文件卡死
        final stream = File(widget.file.path).openRead();
        int totalBytes = 0;
        await for (final chunk in stream) {
          totalBytes += chunk.length;
          if (totalBytes > _maxPreviewBytes) {
            final remaining = _maxPreviewBytes - (totalBytes - chunk.length);
            if (remaining > 0) {
              buffer.addAll(chunk.sublist(0, remaining));
            }
            truncated = true;
            break;
          }
          buffer.addAll(chunk);
        }
      }

      if (mounted) {
        setState(() {
          _content = utf8.decode(buffer, allowMalformed: true);
          _truncated = truncated;
          _loading = false;
        });
      }
    } catch (e) {
      // 内存溢出或其他异常，提示用系统软件打开
      if (mounted) {
        setState(() {
          _tooLarge = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.iconActive),
      );
    }

    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.textHint),
            const SizedBox(height: 12),
            Text(
              AppStrings.fileLoadFailed,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    // 文件过大或内存溢出，提示用系统软件打开
    if (_tooLarge) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description, size: 64, color: colors.textHint),
              const SizedBox(height: 16),
              Text(
                '文件过大，无法在应用内预览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请使用系统软件打开查看完整内容',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              if (widget.remoteDeviceIp == null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => OpenFilex.open(widget.file.path),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('使用系统软件打开'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              _content ?? '',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colors.textPrimary,
                fontFamily: PlatformUtils.systemFontFamily,
              ),
            ),
            if (_truncated)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.inputBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '文件过大，仅显示前 512KB 内容。请使用系统应用打开查看完整内容。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 不支持的文件格式预览器
// =============================================================================

class _UnsupportedViewer extends StatelessWidget {
  final FileItem file;

  const _UnsupportedViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final typeColor = file.typeColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 封面图标
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: colors.cardBg,
                border: Border.all(
                  color: colors.inputBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(file.typeIcon, size: 48, color: typeColor),
                  const SizedBox(height: 8),
                  if (file.extension.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        file.extension.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: typeColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 文件名
            Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            // 提示标题
            Text(
              AppStrings.unsupportedFileTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            // 提示描述
            Text(
              AppStrings.unsupportedFileDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textHint,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
