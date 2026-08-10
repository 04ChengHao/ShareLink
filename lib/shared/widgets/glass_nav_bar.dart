import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 手机端悬浮胶囊底部导航栏
///
/// 无背景容器，仅通过滑动胶囊指示当前激活项。
/// 切换时胶囊从上一个 tab 平滑滑动到当前 tab。
class GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavDestination> destinations;

  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final activeColor = theme.colorScheme.primary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: colors.glassBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / destinations.length;

              return Stack(
                children: [
                  // 滑动胶囊（从上一个 tab 平滑滑动到当前 tab）
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: selectedIndex * itemWidth,
                    width: itemWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? activeColor.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Tab 项（图标 + 激活时展开文字）
                  Row(
                    children: List.generate(destinations.length, (index) {
                      final isSelected = index == selectedIndex;
                      final destination = destinations[index];
                      final color = isSelected
                          ? activeColor
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.5)
                              : colors.textSecondary);

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onDestinationSelected(index),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? destination.selectedIcon
                                      : destination.icon,
                                  size: 22,
                                  color: color,
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                  child: isSelected
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                              left: 6),
                                          child: Text(
                                            destination.label,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: color,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class GlassNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const GlassNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
