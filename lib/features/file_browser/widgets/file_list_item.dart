import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/app_image_cache_manager.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';
import '../services/local_file_service.dart';
import '../services/remote_file_service.dart';

/// 文件列表项（上方封面，下方文件名）
/// 点击效果为封面缩放动画
///
/// 支持本机和远程文件封面：
/// - 本机图片：Image.file
/// - 远程图片：CachedNetworkImage（磁盘持久化缓存，避免重复下载）
/// - 本机视频：本地生成缩略图
/// - 远程视频：通过 HTTP 请求远程缩略图（同样使用缓存）
class FileListItem extends ConsumerStatefulWidget {
  final FileItem file;
  final bool showFileName;
  final VoidCallback? onTap;

  /// 远程设备 IP（null 表示本机文件）
  final String? remoteDeviceIp;

  /// 长按（手机）/ 右键（桌面）回调，用于弹出操作栏
  ///
  /// 传入卡片自身的 [BuildContext] 用于定位操作栏在卡片上方。
  final void Function(BuildContext cardContext)? onShowActions;

  const FileListItem({
    super.key,
    required this.file,
    this.showFileName = true,
    this.onTap,
    this.remoteDeviceIp,
    this.onShowActions,
  });

  @override
  ConsumerState<FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends ConsumerState<FileListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown() {
    _scaleController.forward();
  }

  void _onTapUp() {
    _scaleController.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 封面区域（带缩放点击效果）
        Expanded(
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(),
            onTapUp: (_) => _onTapUp(),
            onTapCancel: _onTapCancel,
            onLongPress: () => widget.onShowActions?.call(context),
            onSecondaryTap: () => widget.onShowActions?.call(context),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildCover(colors),
            ),
          ),
        ),
        // 文件名区域（固定高度占位）
        SizedBox(
          height: 28,
          child: widget.showFileName
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    widget.file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  /// 构建封面
  Widget _buildCover(AppColorScheme colors) {
    final typeColor = widget.file.typeColor;

    if (widget.file.isImage) {
      return _ImageCover(
        imagePath: widget.file.path,
        typeColor: typeColor,
        remoteDeviceIp: widget.remoteDeviceIp,
      );
    }

    if (widget.file.isVideo) {
      return _VideoThumbnailCover(
        videoPath: widget.file.path,
        typeColor: typeColor,
        remoteDeviceIp: widget.remoteDeviceIp,
      );
    }

    // 其他文件：文件类型图标或后缀名当封面
    return _PlainCover(
      typeColor: typeColor,
      icon: widget.file.typeIcon,
      extension: widget.file.extension,
      cardBg: colors.cardBg,
      inputBorder: colors.inputBorder,
    );
  }
}

/// 透明网格背景占位（用于图片缩略图）
///
/// 使用棋盘格让透明图片的透明区域可见，避免使用渐变色影响判断。
/// [showIcon] 为 true 时居中显示类型图标（加载中/失败占位），
/// 作为透明图片的网格背景时传 false，只保留棋盘格不显示图标。
class _GridPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool showIcon;

  const _GridPlaceholder({
    required this.icon,
    required this.iconColor,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _CheckerPainter()),
        if (showIcon)
          Center(child: Icon(icon, size: 36, color: iconColor)),
      ],
    );
  }
}

/// 棋盘格画笔
class _CheckerPainter extends CustomPainter {
  static const double _cellSize = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = const Color(0xFFF0F0F0);
    final darkPaint = Paint()..color = const Color(0xFFD6D6D6);

    canvas.drawRect(Offset.zero & size, lightPaint);

    for (double y = 0; y < size.height; y += _cellSize) {
      for (double x = 0; x < size.width; x += _cellSize) {
        final cellIndex = (x / _cellSize).floor() + (y / _cellSize).floor();
        if (cellIndex.isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, _cellSize, _cellSize),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 播放图标叠加
Widget _buildPlayBadge() {
  return Positioned(
    bottom: 6,
    right: 6,
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.play_arrow,
        size: 14,
        color: Colors.white,
      ),
    ),
  );
}

/// 纯色封面（非图片/视频文件）
class _PlainCover extends StatelessWidget {
  final Color typeColor;
  final IconData icon;
  final String extension;
  final Color cardBg;
  final Color inputBorder;

  const _PlainCover({
    required this.typeColor,
    required this.icon,
    required this.extension,
    required this.cardBg,
    required this.inputBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inputBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: typeColor),
          const SizedBox(height: 4),
          if (extension.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                extension.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: typeColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 图片封面
///
/// - 远程：使用 [CachedNetworkImage] 实现磁盘持久化缓存
///   （滑动离开再回来不会重新下载）
/// - 本机：使用 [Image.file] 配合 Flutter 内置图片缓存
///
/// 占位符使用透明网格背景（棋盘格），而非渐变色，
/// 让用户能直观判断图片是否为透明图片。
///
/// 注意：本机图片**首帧直接构建 Image**（不做"等一帧再加载"的延迟处理）。
/// 图片缓存命中时同帧渲染，不出现「占位图 → 图片」的闪烁；
/// 未命中时棋盘格背景自然透出，也不会有图标占位的突变。
class _ImageCover extends StatelessWidget {
  final String imagePath;
  final Color typeColor;
  final String? remoteDeviceIp;

  const _ImageCover({
    required this.imagePath,
    required this.typeColor,
    this.remoteDeviceIp,
  });

  @override
  Widget build(BuildContext context) {
    final isRemote = remoteDeviceIp != null;

    if (isRemote) {
      // 远程：使用 CachedNetworkImage 实现磁盘缓存
      final url = RemoteFileService.instance.buildFileUrl(
        remoteDeviceIp!,
        imagePath,
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 远程透明图片同样垫上棋盘格，透明区域可见（与本地一致）
            _GridPlaceholder(
              icon: Icons.image,
              iconColor: typeColor,
              showIcon: false,
            ),
            CachedNetworkImage(
              imageUrl: url,
              cacheManager: AppImageCacheManager.instance,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    // 本机：使用 Image.file（Flutter 内置缓存，命中时同帧渲染不闪烁）
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 网格背景作为占位（本地缩略图保留棋盘格，透明区域可见）
          const _GridPlaceholder(
            icon: Icons.image,
            iconColor: Color(0xFF8E8E93),
            showIcon: false,
          ),
          Image(
            image: ResizeImage(FileImage(File(imagePath)), width: 300),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // frame == null：尚未解码完成，透出底部棋盘格（无图标突变）
              if (frame == null) return const SizedBox.shrink();
              return child;
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 视频缩略图封面
///
/// - 远程：使用 [CachedNetworkImage] 实现磁盘持久化缓存
/// - 本机：本地生成缩略图
class _VideoThumbnailCover extends ConsumerStatefulWidget {
  final String videoPath;
  final Color typeColor;
  final String? remoteDeviceIp;

  const _VideoThumbnailCover({
    required this.videoPath,
    required this.typeColor,
    this.remoteDeviceIp,
  });

  @override
  ConsumerState<_VideoThumbnailCover> createState() =>
      _VideoThumbnailCoverState();
}

class _VideoThumbnailCoverState extends ConsumerState<_VideoThumbnailCover> {
  String? _thumbnailUrl;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 本机模式：同步命中已生成的缩略图 → 首帧直接渲染，避免占位图闪烁
    if (widget.remoteDeviceIp == null) {
      final path = LocalFileService.instance.peekThumbnail(widget.videoPath);
      if (path != null) {
        _thumbnailUrl = path;
        _loading = false;
      }
    }
    // 未同步命中：等第一帧渲染完成后再异步加载/生成缩略图
    if (_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startLoadingThumbnail();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnailCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设备/路径变化：先尝试同步命中新路径的缩略图，未命中再异步加载
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.remoteDeviceIp != widget.remoteDeviceIp) {
      String? path;
      if (widget.remoteDeviceIp == null) {
        path = LocalFileService.instance.peekThumbnail(widget.videoPath);
      }
      if (path != null) {
        _thumbnailUrl = path;
        _loading = false;
        _failed = false;
      } else {
        _thumbnailUrl = null;
        _loading = true;
        _failed = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startLoadingThumbnail();
        });
      }
    }
  }

  void _startLoadingThumbnail() {
    if (widget.remoteDeviceIp != null) {
      // 远程模式：直接构建缩略图 URL，由 CachedNetworkImage 加载
      setState(() {
        _thumbnailUrl = RemoteFileService.instance.buildThumbnailUrl(
          widget.remoteDeviceIp!,
          widget.videoPath,
        );
        _loading = false;
      });
    } else {
      // 本机模式：本地生成缩略图
      _generateThumbnail();
    }
  }

  Future<void> _generateThumbnail() async {
    final service = ref.read(localFileServiceProvider);
    final result = await service.getVideoThumbnail(widget.videoPath);
    if (mounted) {
      setState(() {
        _thumbnailUrl = result;
        _loading = false;
        _failed = result == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 加载中或失败：显示网格占位 + 播放图标
    if (_loading || _failed || _thumbnailUrl == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _GridPlaceholder(
              icon: Icons.video_file,
              iconColor: widget.typeColor,
            ),
            _buildPlayBadge(),
          ],
        ),
      );
    }

    final isRemote = widget.remoteDeviceIp != null;

    if (isRemote) {
      // 远程：使用 CachedNetworkImage 缓存
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 远程透明视频缩略图同样垫上棋盘格（与本地一致）
            _GridPlaceholder(
              icon: Icons.video_file,
              iconColor: widget.typeColor,
              showIcon: false,
            ),
            CachedNetworkImage(
              imageUrl: _thumbnailUrl!,
              cacheManager: AppImageCacheManager.instance,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
            _buildPlayBadge(),
          ],
        ),
      );
    }

    // 本机：使用 Image.file（本地视频缩略图保留棋盘格背景）
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _GridPlaceholder(
            icon: Icons.video_file,
            iconColor: widget.typeColor,
            showIcon: false,
          ),
          Image(
            image: ResizeImage(FileImage(File(_thumbnailUrl!)), width: 300),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // 未解码完成时透出棋盘格，解码后同帧渲染（无闪烁）
              if (frame == null) return const SizedBox.shrink();
              return child;
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          _buildPlayBadge(),
        ],
      ),
    );
  }
}
