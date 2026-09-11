import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'liquid_glass.dart';

/// 自定义玻璃风格下拉框
///
/// 与应用整体玻璃拟态风格统一，替代 Material 默认 DropdownButton。
class GlassDropdownField<T> extends StatefulWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? labelText;
  final IconData? prefixIcon;
  final double borderRadius;

  const GlassDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.prefixIcon,
    this.borderRadius = 12,
  });

  @override
  State<GlassDropdownField<T>> createState() => _GlassDropdownFieldState<T>();
}

class _GlassDropdownFieldState<T> extends State<GlassDropdownField<T>> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
      return;
    }
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _DropdownOverlay<T>(
        targetSize: size,
        layerLink: _layerLink,
        items: widget.items,
        currentValue: widget.value,
        onSelect: (value) {
          widget.onChanged(value);
          // 移除动作交给浮层：先播完「向上缩短」消失动画，再由 onDismiss 关闭
        },
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
    _isOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleOverlay,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                // 白色发光：液态玻璃质感
                BoxShadow(
                  color: Colors.white
                      .withValues(alpha: colors.isDark ? 0.18 : 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
                // 黑色投影：浅色模式下保证控件脱离白色底板、边界清晰可见
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: colors.isDark ? 0.25 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    // 液态玻璃渐变：透明度适中，深色模式下仍可见且不会过白
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors.isDark
                          ? [
                              Colors.white.withValues(alpha: 0.16),
                              Colors.white.withValues(alpha: 0.08),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.72),
                              Colors.white.withValues(alpha: 0.45),
                            ],
                    ),
                    borderRadius:
                        BorderRadius.circular(widget.borderRadius),
                    // 浅色模式边框需可见：白色底板上白色描边看不清 → 用淡黑
                    border: Border.all(
                      color: colors.isDark
                          ? colors.glassBorder
                          : Colors.black.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.prefixIcon != null) ...[
                        Icon(
                          widget.prefixIcon,
                          size: 20,
                          color: colors.iconSecondary,
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (widget.labelText != null) ...[
                        Text(
                          widget.labelText!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(child: selectedItem.child),
                      AnimatedRotation(
                        turns: _isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: colors.iconSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 下拉浮层
class _DropdownOverlay<T> extends StatefulWidget {
  final Size targetSize;
  final LayerLink layerLink;
  final List<DropdownMenuItem<T>> items;
  final T currentValue;
  final ValueChanged<T?> onSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.targetSize,
    required this.layerLink,
    required this.items,
    required this.currentValue,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_DropdownOverlay<T>> createState() => _DropdownOverlayState<T>();
}

class _DropdownOverlayState<T> extends State<_DropdownOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final double _targetHeight;

  // 单行高度估计（含较大内边距，用于滑出动画的上限估算）
  static const double _rowHeight = 60;

  // 关闭动画是否已触发，避免重复 reverse 导致回调多次
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // 目标高度上限：取较大估计值，配合 ConstrainedBox(maxHeight) +
    // shrinkWrap 的 ListView 自适应实际内容高度，避免底部多出空白。
    _targetHeight =
        (widget.items.length * _rowHeight).clamp(0.0, 300.0).toDouble();
    // 滑出/消失动画：正向从 0 增长铺开（弹出），反向向上缩短并淡出
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 触发关闭动画：向上缩短并淡出，结束后通知父级移除浮层
  void _close() {
    if (_closing) return;
    _closing = true;
    _controller.reverse().whenComplete(() {
      if (mounted) widget.onDismiss();
    });
  }

  /// 选中某项：先回传新值，再播完关闭动画
  void _handleSelect(T? value) {
    widget.onSelect(value);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 遮罩层，点击淡出关闭
        GestureDetector(
          onTap: _close,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, _) {
              final t = _scale.value.clamp(0.0, 1.0);
              return Opacity(
                // 高度缩短同时淡出，形成「向上缩短消失」反馈
                opacity: t,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: widget.targetSize.width,
                    // 高度上限随动画增长（弹出）/ 缩短（消失）；ListView
                    // shrinkWrap 自适应实际内容高度，内容小于上限时贴合内容
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 0,
                        maxHeight: _targetHeight * t,
                      ),
                      child: LiquidGlassContainer(
                        elevated: true,
                        radius: 14,
                        blur: 16,
                        intensity: 1.15,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          children: widget.items.map((item) {
                            final isSelected =
                                item.value == widget.currentValue;
                            return _DropdownItem<T>(
                              item: item,
                              isSelected: isSelected,
                              onTap: () => _handleSelect(item.value),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DropdownItem<T> extends StatefulWidget {
  final DropdownMenuItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  const _DropdownItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_DropdownItem<T>> createState() => _DropdownItemState<T>();
}

class _DropdownItemState<T> extends State<_DropdownItem<T>> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: widget.isSelected
              ? GlassCapsuleDecoration.build(colors, 10, strong: false)
              : BoxDecoration(
                  color: _hovering ? colors.inputBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
          child: Row(
            children: [
              Expanded(child: widget.item.child),
              if (widget.isSelected)
                Icon(Icons.check_rounded, size: 18, color: colors.iconActive),
            ],
          ),
        ),
      ),
    );
  }
}
