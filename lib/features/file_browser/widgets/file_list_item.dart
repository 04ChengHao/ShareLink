import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../models/file_item.dart';
import '../providers/file_browser_provider.dart';

/// 文件列表项（上方封面，下方文件名）
/// 点击效果为封面缩放动画
class FileListItem extends ConsumerStatefulWidget {
  final FileItem file;
  final bool showFileName;
  final VoidCallback? onTap;

  const FileListItem({
    super.key,
    required this.file,
    this.showFileName = true,
    this.onTap,
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
      return _ImageCover(imagePath: widget.file.path, typeColor: typeColor);
    }

    if (widget.file.isVideo) {
      return _VideoThumbnailCover(
        videoPath: widget.file.path,
        typeColor: typeColor,
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

/// 构建默认封面背景（渐变 + 图标）
Widget _buildGradientCover(Color typeColor, IconData icon) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          typeColor.withValues(alpha: 0.3),
          typeColor.withValues(alpha: 0.1),
        ],
      ),
    ),
    child: Center(
      child: Icon(icon, size: 36, color: typeColor),
    ),
  );
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

/// 图片封面：先显示默认渐变封面，图片加载完成后淡入替换
class _ImageCover extends StatefulWidget {
  final String imagePath;
  final Color typeColor;

  const _ImageCover({
    required this.imagePath,
    required this.typeColor,
  });

  @override
  State<_ImageCover> createState() => _ImageCoverState();
}

class _ImageCoverState extends State<_ImageCover> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 默认渐变背景（始终作为底层占位）
          _buildGradientCover(widget.typeColor, Icons.image),

          // 图片（使用 cacheWidth 降低内存，避免大图卡顿）
          Image.file(
            File(widget.imagePath),
            fit: BoxFit.cover,
            cacheWidth: 256,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame == null) {
                // 图片还在加载中，显示默认封面
                return const SizedBox.shrink();
              }
              // 图片加载完成，淡入显示
              return AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 视频缩略图封面：先显示默认渐变封面，缩略图生成后淡入替换
class _VideoThumbnailCover extends ConsumerStatefulWidget {
  final String videoPath;
  final Color typeColor;

  const _VideoThumbnailCover({
    required this.videoPath,
    required this.typeColor,
  });

  @override
  ConsumerState<_VideoThumbnailCover> createState() =>
      _VideoThumbnailCoverState();
}

class _VideoThumbnailCoverState extends ConsumerState<_VideoThumbnailCover> {
  String? _thumbnailPath;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    final service = ref.read(localFileServiceProvider);
    final result = await service.getVideoThumbnail(widget.videoPath);
    if (mounted) {
      setState(() {
        _thumbnailPath = result;
        _loading = false;
        _failed = result == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 加载中或失败：显示默认渐变封面 + 播放图标
    if (_loading || _failed || _thumbnailPath == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildGradientCover(widget.typeColor, Icons.video_file),
          _buildPlayBadge(),
        ],
      );
    }

    // 成功：显示缩略图 + 播放图标
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 默认渐变背景作为占位
          _buildGradientCover(widget.typeColor, Icons.video_file),
          // 缩略图淡入
          Image.file(
            File(_thumbnailPath!),
            fit: BoxFit.cover,
            cacheWidth: 256,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame == null) return const SizedBox.shrink();
              return AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          _buildPlayBadge(),
        ],
      ),
    );
  }
}
