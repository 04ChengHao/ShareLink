import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

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

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.inputBg,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: colors.inputBorder),
        boxShadow: [
          BoxShadow(
            color: colors.isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, 1),
            blurRadius: 2,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.8),
            offset: const Offset(0, -1),
            blurRadius: 1,
            spreadRadius: 0,
          ),
        ],
      ),
      child: widget.multiSelect
          ? _buildMultiSelect(colors)
          : _buildSingleSelect(colors),
    );
  }

  /// 单选模式：滑动胶囊
  Widget _buildSingleSelect(AppColorScheme colors) {
    final selectedIndex = widget.items
        .indexWhere((item) => widget.selectedValues.contains(item.value));
    final activeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / widget.items.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 滑动胶囊
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              left: activeIndex * tabWidth + 2,
              top: 2,
              bottom: 2,
              width: tabWidth - 4,
              child: _buildCapsule(colors),
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
                    child: _buildTabContent(item, isSelected, colors),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  /// 多选模式：每个 tab 独立胶囊
  Widget _buildMultiSelect(AppColorScheme colors) {
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
              margin: const EdgeInsets.all(2),
              decoration: isSelected
                  ? BoxDecoration(
                      color: colors.primaryWithAlpha(0.12),
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius - 2),
                      border:
                          Border.all(color: colors.primaryWithAlpha(0.3)),
                    )
                  : null,
              child: _buildTabContent(item, isSelected, colors),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 激活胶囊
  Widget _buildCapsule(AppColorScheme colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryWithAlpha(0.12),
        borderRadius: BorderRadius.circular(widget.borderRadius - 2),
        border: Border.all(color: colors.primaryWithAlpha(0.3)),
      ),
    );
  }

  /// Tab 内容
  Widget _buildTabContent(
    SegmentedTabItem<T> item,
    bool isSelected,
    AppColorScheme colors,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isSelected ? colors.iconActive : colors.iconSecondary,
            ),
            if (item.label != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isSelected ? colors.iconActive : colors.textSecondary,
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
