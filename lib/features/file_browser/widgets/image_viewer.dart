import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/platform_utils.dart';
import '../services/remote_file_service.dart';

/// 图片查看器（沉浸式全屏预览）
///
/// **布局**：
/// - 顶部胶囊：返回按钮、标题、系统打开按钮
/// - 底部胶囊：缩小、缩放比例、放大、旋转、还原
/// - 点击屏幕：隐藏/显示所有控制栏
///
/// **桌面端**：
/// - 鼠标滚轮：以鼠标位置为中心缩放
///
/// **手机端**：
/// - 双指缩放（以手指中心位置）
/// - 双击放大/还原
///
/// **透明图片背景**：使用透明网格背景（棋盘格）
///
/// **还原按钮**：回到contained铺满并居中
class ImageViewer extends StatefulWidget {
  final String imagePath;
  final String? remoteDeviceIp;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 使用系统软件打开回调
  final VoidCallback? onOpenWithSystem;

  const ImageViewer({
    super.key,
    required this.imagePath,
    this.remoteDeviceIp,
    this.onBack,
    this.onOpenWithSystem,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PhotoViewController _controller;
  late final PhotoViewScaleStateController _scaleStateController;

  bool _showControls = true;
  double _rotation = 0.0;

  // 初始缩放比例（图片首次加载后的 contained 缩放）
  double? _initialScale;

  /// 缩放范围：20% ~ 500%
  static const double _minScale = 0.2;
  static const double _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    _controller = PhotoViewController();
    _scaleStateController = PhotoViewScaleStateController();
    _controller.outputStateStream.listen((value) {
      if (_initialScale == null && value.scale != null) {
        _initialScale = value.scale;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scaleStateController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _zoomIn() {
    final current = _controller.value.scale ?? _initialScale ?? 1.0;
    _controller.scale = (current * 1.25).clamp(_minScale, _maxScale);
  }

  void _zoomOut() {
    final current = _controller.value.scale ?? _initialScale ?? 1.0;
    _controller.scale = (current / 1.25).clamp(_minScale, _maxScale);
  }

  void _rotate() {
    // 仅旋转、不放大不缩小：记录旋转前比例，旋转后恢复，并让回中；
    // 不重建 PhotoView，避免闪屏
    final prevScale = _controller.value.scale ?? _initialScale ?? 1.0;
    setState(() => _rotation += 90.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.scale = prevScale.clamp(_minScale, _maxScale);
      _controller.position = Offset.zero;
    });
  }

  void _reset() {
    // 回到 0°（未旋转方向），并用 ScaleStateController 强制 contained 铺满并居中，
    // 从根本上消除旋转+滑动后的偏移
    setState(() => _rotation = 0.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scaleStateController.scaleState = PhotoViewScaleState.initial;
      _controller.position = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isRemote = widget.remoteDeviceIp != null;
    final imageProvider = isRemote
        ? NetworkImage(
            RemoteFileService.instance.buildFileUrl(
              widget.remoteDeviceIp!,
              widget.imagePath,
            ),
          ) as ImageProvider
        : FileImage(File(widget.imagePath));

    return Scaffold(
      backgroundColor: const Color(0xFF161616),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 透明网格背景（棋盘格）：垫在图片下，透明区域可见
          const _TransparentGridBackground(),

          // 图片（旋转在 PhotoView 内部实现，使触摸移动方向与视觉一致）
          GestureDetector(
            onTap: _toggleControls,
            child: _PlatformPhotoView(
              controller: _controller,
              scaleStateController: _scaleStateController,
              imageProvider: imageProvider,
              colors: colors,
              rotationRadians: _rotation * math.pi / 180,
            ),
          ),

          // 顶部胶囊控制栏
          if (_showControls) _buildTopBar(),

          // 底部缩放控制台
          if (_showControls) _buildBottomBar(),
        ],
      ),
    );
  }

  /// 顶部胶囊：返回、标题、系统打开
  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          // 返回按钮
          if (widget.onBack != null)
            _CapsuleIconButton(
              icon: Icons.arrow_back,
              tooltip: '返回',
              onTap: widget.onBack!,
            ),
          if (widget.onBack != null) const SizedBox(width: 8),
          // 标题
          Expanded(
            child: _CapsuleLabel(
              text: widget.imagePath.split(RegExp(r'[/\\]')).last,
            ),
          ),
          const SizedBox(width: 8),
          // 系统打开按钮
          if (widget.onOpenWithSystem != null)
            _CapsuleIconButton(
              icon: Icons.open_in_new,
              tooltip: AppStrings.openWithSystem,
              onTap: widget.onOpenWithSystem!,
            ),
        ],
      ),
    );
  }

  /// 底部缩放控制台：缩小、比例、放大、旋转、还原
  Widget _buildBottomBar() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 0,
      right: 0,
      child: Center(
        child: _CapsuleGroup(
          children: [
            _CapsuleIconButton(
              icon: Icons.zoom_out,
              tooltip: '缩小',
              onTap: _zoomOut,
            ),
            StreamBuilder<PhotoViewControllerValue>(
              stream: _controller.outputStateStream,
              initialData: _controller.value,
              builder: (_, snapshot) {
                final scale = snapshot.data?.scale ?? _initialScale ?? 1.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${(scale * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
            _CapsuleIconButton(
              icon: Icons.zoom_in,
              tooltip: '放大',
              onTap: _zoomIn,
            ),
            _CapsuleIconButton(
              icon: Icons.rotate_right,
              tooltip: '旋转 90',
              onTap: _rotate,
            ),
            _CapsuleIconButton(
              icon: Icons.refresh,
              tooltip: '还原',
              onTap: _reset,
            ),
          ],
        ),
      ),
    );
  }
}
/// 平台感知的 PhotoView（旋转在内部实现，保证触摸移动方向与视觉一致）
///
/// 通过显式传入“旋转后交换的宽高”作为 childSize，使缩放/平移边界覆盖旋转后
/// 的最长边（旋转后宽度 = 原长度，可平移看到细节）。
/// 不设置 filterQuality（保持 none）以免图片被放大错乱；用同一个
/// PhotoView 实例 + ScaleStateController，避免旋转时重建引起的闪屏。
class _PlatformPhotoView extends StatefulWidget {
  final PhotoViewController controller;
  final PhotoViewScaleStateController scaleStateController;
  final ImageProvider imageProvider;
  final AppColorScheme colors;
  final double rotationRadians;

  const _PlatformPhotoView({
    super.key,
    required this.controller,
    required this.scaleStateController,
    required this.imageProvider,
    required this.colors,
    this.rotationRadians = 0,
  });

  @override
  State<_PlatformPhotoView> createState() => _PlatformPhotoViewState();
}

class _PlatformPhotoViewState extends State<_PlatformPhotoView> {
  Offset _mousePosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.isDesktop;
    // 旋转量化到 90° 倍数
    final turns = (widget.rotationRadians / (math.pi / 2)).round() % 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final outer = constraints.biggest;
        final swapped = turns.isOdd;
        // 旋转后内容外接盒尺寸：90°/270° 交换宽高，覆盖旋转后的最长边
        final childSize = Size(
          swapped ? outer.height : outer.width,
          swapped ? outer.width : outer.height,
        );

        final photoView = PhotoView.customChild(
          controller: widget.controller,
          scaleStateController: widget.scaleStateController,
          // 显式传入旋转后的尺寸，让缩放/平移边界随旋转变化
          childSize: childSize,
          minScale: _ImageViewerState._minScale,
          maxScale: _ImageViewerState._maxScale,
          initialScale: PhotoViewComputedScale.contained,
          basePosition: Alignment.center,
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          gestureDetectorBehavior: HitTestBehavior.opaque,
          child: RotatedBox(
            quarterTurns: turns,
            child: Image(
              image: widget.imageProvider,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: frame == null
                      ? Center(
                          child: CircularProgressIndicator(
                            color: widget.colors.iconActive,
                          ),
                        )
                      : child,
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image,
                      size: 64,
                      color: widget.colors.textHint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.fileLoadFailed,
                      style: TextStyle(color: widget.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (!isDesktop) {
          return photoView;
        }

        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerHover: (event) {
            _mousePosition = event.position;
          },
          child: photoView,
        );
      },
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final currentScale = widget.controller.value.scale ?? 1.0;
      final direction = event.scrollDelta.dy > 0 ? -1 : 1;
      final newScale = (currentScale * (1 + direction * 0.15))
          .clamp(_ImageViewerState._minScale, _ImageViewerState._maxScale);

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final center = renderBox.size.center(Offset.zero);
      final mouseLocal = renderBox.globalToLocal(_mousePosition);
      final offsetFromCenter = mouseLocal - center;

      final currentPosition = widget.controller.value.position;
      final scaleRatio = newScale / currentScale;
      final newPosition = currentPosition -
          offsetFromCenter * (scaleRatio - 1);

      widget.controller.scale = newScale;
      widget.controller.position = newPosition;
    }
  }
}

/// 透明网格背景（棋盘格）
class _TransparentGridBackground extends StatelessWidget {
  const _TransparentGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      size: Size.infinite,
    );
  }
}

class _GridPainter extends CustomPainter {
  static const double _cellSize = 16.0;
  static const Color _lightColor = Color(0xFFE8E8E8);
  static const Color _darkColor = Color(0xFFC8C8C8);

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = _lightColor;
    final darkPaint = Paint()..color = _darkColor;

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

// =============================================================================
// 胶囊悬浮组件
// =============================================================================

class _CapsuleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CapsuleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      verticalOffset: 32,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class _CapsuleLabel extends StatelessWidget {
  final String text;

  const _CapsuleLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CapsuleGroup extends StatelessWidget {
  final List<Widget> children;

  const _CapsuleGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 去除左右内边距，使弧度和胶囊按钮重合更美观
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}