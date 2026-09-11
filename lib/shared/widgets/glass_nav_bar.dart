import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 手机端悬浮液态玻璃底部导航栏
///
/// 采用液态玻璃（liquid glass）质感：背景模糊 + 半透明渐变 + 顶部高光描边，
/// 底部叠加主题色发光，让胶囊在列表之上更醒目、悬浮感更强。
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // 常规投影：让胶囊从背景中脱离出来
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              // 底部白色发光：低强度，衬托出胶囊不喧宾夺主
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  // 液态玻璃：低透明度渐变，保持通透又能看清内容
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? const [
                            Color(0x45383842),
                            Color(0x3824242A),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0.35),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // 顶部玻璃高光：液态玻璃质感
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isDark
                                ? [
                                    Colors.white.withValues(alpha: 0.10),
                                    Colors.white.withValues(alpha: 0.0),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.6),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final itemWidth =
                              constraints.maxWidth / destinations.length;

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
                                    // 深色模式用带透明度的白色背景（原为蓝色）
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(18),
                                    // 描边：增强立体分界
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white
                                              .withValues(alpha: 0.28)
                                          : Colors.white
                                              .withValues(alpha: 0.8),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      // 白色发光：激活块高亮，深色模式下同样明显
                                      BoxShadow(
                                        color: Colors.white
                                            .withValues(alpha: 0.6),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                      // 下沉投影：增强深色模式下的立体感
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.35 : 0.08,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Tab 项（图标 + 激活时展开文字）
                              Row(
                                children:
                                    List.generate(destinations.length, (index) {
                                  final isSelected = index == selectedIndex;
                                  final destination = destinations[index];
                                  // 深色模式下激活态用纯白（图标+文字），避免亮蓝刺眼看不清；
                                  // 激活块背景已是半透明白 + 白色描边，白字与之呼应。
                                  final color = isSelected
                                      ? (isDark ? Colors.white : activeColor)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.5)
                                          : colors.textSecondary);

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          onDestinationSelected(index),
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
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              curve: Curves.easeOut,
                                              child: isSelected
                                                  ? Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 6),
                                                      child: Text(
                                                        destination.label,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w600,
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
                  ],
                ),
              ),
            ),
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
