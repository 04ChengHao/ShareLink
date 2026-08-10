import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'window_manager_stub.dart';

/// 桌面端自定义窗口控制按钮（最小化 / 全屏 / 关闭）
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Icons.remove,
          tooltip: '最小化',
          onTap: () => windowManager.minimize(),
        ),
        _ControlButton(
          icon: Icons.crop_square,
          tooltip: '全屏',
          onTap: () async {
            if (await windowManager.isFullScreen()) {
              await windowManager.setFullScreen(false);
            } else {
              await windowManager.setFullScreen(true);
            }
          },
        ),
        _ControlButton(
          icon: Icons.close,
          tooltip: '关闭',
          hoverBackground: const Color(0xFFE81123).withValues(alpha: 0.18),
          pressBackground: const Color(0xFFE81123).withValues(alpha: 0.28),
          hoverForeground: const Color(0xFFE81123),
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color? hoverBackground;
  final Color? pressBackground;
  final Color? hoverForeground;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.hoverBackground,
    this.pressBackground,
    this.hoverForeground,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final backgroundColor = _pressing
        ? (widget.pressBackground ??
              colorScheme.onSurface.withValues(alpha: 0.12))
        : _hovering
        ? (widget.hoverBackground ??
              colorScheme.onSurface.withValues(alpha: 0.08))
        : Colors.transparent;

    final foregroundColor = widget.hoverForeground != null && _hovering
        ? widget.hoverForeground!
        : colorScheme.onSurface;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() {
            _hovering = false;
            _pressing = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 32,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovering || _pressing
                    ? colorScheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _pressing ? 0.88 : 1.0,
              child: Icon(widget.icon, size: 18, color: foregroundColor),
            ),
          ),
        ),
      ),
    );
  }
}
