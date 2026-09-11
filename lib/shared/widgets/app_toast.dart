import 'package:flutter/material.dart';

/// 提示类型（决定图标与颜色）
enum ToastType {
  success,
  info,
  warning,
  error,
}

IconData _iconFor(ToastType type) => switch (type) {
      ToastType.success => Icons.check_circle,
      ToastType.info => Icons.info_outline,
      ToastType.warning => Icons.warning_amber_rounded,
      ToastType.error => Icons.error_outline,
    };

Color _colorFor(ToastType type) => switch (type) {
      ToastType.success => const Color(0xFF4CD964),
      ToastType.info => const Color(0xFF4FC3F7),
      ToastType.warning => const Color(0xFFFFB300),
      ToastType.error => const Color(0xFFFF5252),
    };

/// 在根 Overlay 上显示一次轻提示（Toast）
///
/// 显示在所有弹窗/底部弹窗/抽屉之上，不被 modal barrier 遮挡。
/// 位置固定在屏幕上三分之一处、水平居中；带淡入+缩放出场动画，结束自动淡出。
/// 不同 [ToastType] 使用不同图标与颜色。
void showAppToast(
  BuildContext context,
  String message, {
  ToastType type = ToastType.success,
  Duration duration = const Duration(milliseconds: 1800),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      type: type,
      duration: duration,
      onCompleted: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// 单条 Toast 视图（自带进出场动画）
class _AppToast extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onCompleted;

  const _AppToast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onCompleted,
  });

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  /// 缩放：0.94 -> 1.0，easeOutBack 略带回弹
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = curved;
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    // 从下方 12px 滑入
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curved);

    _controller.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    // 淡出后再移除，避免生硬消失
    await _controller.reverse();
    widget.onCompleted();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 屏幕上三分之一处、水平居中；不贴住状态栏
    return Align(
      alignment: const Alignment(0, -1 / 3),
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            child: _buildBubble(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final color = _colorFor(widget.type);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE6212327),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(widget.type), size: 18, color: color),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              widget.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}