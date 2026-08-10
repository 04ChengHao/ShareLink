import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'neuomorphic_style.dart';

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
          _removeOverlay();
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.inputBg,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: colors.inputBorder),
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

class _DropdownOverlayState<T> extends State<_DropdownOverlay<T>> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Stack(
      children: [
        // 遮罩层，点击关闭
        GestureDetector(
          onTap: widget.onDismiss,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: widget.targetSize.width,
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: colors.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: NeuomorphicStyle.adaptive(
                  theme.brightness,
                  blur: 20,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: widget.items.map((item) {
                    final isSelected = item.value == widget.currentValue;
                    return _DropdownItem<T>(
                      item: item,
                      isSelected: isSelected,
                      onTap: () => widget.onSelect(item.value),
                    );
                  }).toList(),
                ),
              ),
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : _hovering
                ? colors.inputBg
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Expanded(child: widget.item.child),
              if (widget.isSelected)
                Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
