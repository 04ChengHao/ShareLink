import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'liquid_glass.dart';

/// 分段选项卡项
class SegmentedTabItem<T> {
  final T value;
  final IconData icon;
  final String? label;

  const SegmentedTabItem({
    required this.value,
    required this.icon,
    this.label,
  });
}

/// 分段选项卡组件
///
/// 内凹阴影背景 + 边框，内部 tab 共用一个激活胶囊在激活的 tab 之间左右滑动。
/// - 单选模式：胶囊在 tab 间滑动
/// - 多选模式：每个 tab 独立切换激活状态
class SegmentedTab<T> extends StatefulWidget {
  final List<SegmentedTabItem<T>> items;
  final Set<T> selectedValues;
  final bool multiSelect;
  final ValueChanged<Set<T>> onChanged;
  final double height;
  final double borderRadius;

  const SegmentedTab({
    super.key,
    required this.items,
    required this.selectedValues,
    required this.onChanged,
    this.multiSelect = false,
    this.height = 44,
    this.borderRadius = 12,
  });

  @override
  State<SegmentedTab<T>> createState() => _SegmentedTabState<T>();
}

class _SegmentedTabState<T> extends State<SegmentedTab<T>> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    // 激活内容颜色：与 tabbar 一致——深色模式用白字呼应半透明白胶囊，浅色用主色
    final activeColor =
        colors.isDark ? Colors.white : Theme.of(context).colorScheme.primary;

    // 外层液态玻璃容器：半透明玻璃底 + 白色发光，内部激活胶囊悬浮其上
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.glassBg,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: colors.isDark ? 0.12 : 0.45),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: widget.multiSelect
          ? _buildMultiSelect(colors, activeColor)
          : _buildSingleSelect(colors, activeColor),
    );
  }

  /// 单选模式：一个激活胶囊在选项之间滑动（同 tabbar）
  Widget _buildSingleSelect(AppColorScheme colors, Color activeColor) {
    final selectedIndex = widget.items
        .indexWhere((item) => widget.selectedValues.contains(item.value));
    final activeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / widget.items.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 滑动胶囊（液态玻璃激活块）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              left: activeIndex * tabWidth + 3,
              top: 3,
              bottom: 3,
              width: tabWidth - 6,
              child: DecoratedBox(
                decoration: GlassCapsuleDecoration.build(
                  colors,
                  widget.borderRadius - 3,
                ),
              ),
            ),
            // Tab 项
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.items.map((item) {
                final isSelected = widget.selectedValues.contains(item.value);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _handleSingleSelect(item.value),
                    behavior: HitTestBehavior.opaque,
                    child: _buildTabContent(
                      item,
                      isSelected,
                      colors,
                      activeColor,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  /// 多选模式：每个 tab 独立切换激活块（各选项独立发光胶囊）
  Widget _buildMultiSelect(AppColorScheme colors, Color activeColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.items.map((item) {
        final isSelected = widget.selectedValues.contains(item.value);
        return Expanded(
          child: GestureDetector(
            onTap: () => _handleMultiSelect(item.value),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: const EdgeInsets.all(3),
              decoration: isSelected
                  ? GlassCapsuleDecoration.build(
                      colors,
                      widget.borderRadius - 3,
                      strong: false,
                    )
                  : BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius - 3),
                    ),
              child: _buildTabContent(item, isSelected, colors, activeColor),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Tab 内容
  Widget _buildTabContent(
    SegmentedTabItem<T> item,
    bool isSelected,
    AppColorScheme colors,
    Color activeColor,
  ) {
    final color = isSelected ? activeColor : colors.textSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 20, color: color),
            if (item.label != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleSingleSelect(T value) {
    widget.onChanged({value});
  }

  void _handleMultiSelect(T value) {
    final newSet = Set<T>.from(widget.selectedValues);
    if (newSet.contains(value)) {
      newSet.remove(value);
    } else {
      newSet.add(value);
    }
    widget.onChanged(newSet);
  }
}
