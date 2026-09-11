import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 液态玻璃容器（Liquid Glass）
///
/// 复用底部导航栏（GlassNavBar）的液态玻璃质感：背景模糊 + 半透明渐变 +
/// 顶部高光 + 发光投影。用于关于弹窗表格、下拉选项面板等需要统一玻璃风格的地方。
class LiquidGlassContainer extends StatelessWidget {
  /// 内容（在玻璃层之上）
  final Widget child;

  /// 圆角
  final double radius;

  /// 内容内边距
  final EdgeInsets? padding;

  /// 是否是「浮层/胶囊」（higher），用于加强投影与发光
  final bool elevated;

  /// 模糊强度
  final double blur;

  /// 玻璃质感强度系数（1.0 为标准 tabbar 质感，浮层可更高）
  final double intensity;

  /// 是否绘制顶部玻璃高光条。默认开启用于浮层面板增加通透感；
  /// 在信息密集的表格（如关于弹窗）中该高光会与首行叠成"玻璃里嵌玻璃"的细边，
  /// 需要置为 false。
  final bool sheen;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding,
    this.elevated = false,
    this.blur = 14,
    this.intensity = 1.0,
    this.sheen = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final isDark = colors.isDark;
    final effIntensity = (elevated ? 1.2 : 1.0) * intensity;

    BoxShadow _glow(Color color, double alpha, double blurR,
            [Offset? offset]) =>
        BoxShadow(
          color: color.withValues(
            alpha: (alpha * effIntensity).clamp(0.0, 1.0),
          ),
          blurRadius: blurR,
          offset: offset ?? Offset.zero,
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          // 常规投影：让面板从背景中脱离（与 tabbar 一致）
          _glow(Colors.black, isDark ? 0.3 : 0.1, 16, const Offset(0, 6)),
          // 白色发光：液态玻璃高光（与 tabbar 外框一致，保证统一发光强度）
          _glow(Colors.white, isDark ? 0.22 : 0.3, 20, const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(
                          alpha: (0.16 * effIntensity).clamp(0.0, 0.3),
                        ),
                        Colors.white.withValues(
                          alpha: (0.08 * effIntensity).clamp(0.0, 0.2),
                        ),
                      ]
                    : [
                        Colors.white.withValues(
                          alpha: (0.55 * effIntensity).clamp(0.0, 0.9),
                        ),
                        Colors.white.withValues(
                          alpha: (0.35 * effIntensity).clamp(0.0, 0.7),
                        ),
                      ],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // 顶部玻璃高光：液态玻璃质感（信息密集表格场景可关闭）
                if (sheen)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 18,
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
                                  Colors.white.withValues(alpha: 0.5),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(radius),
                        ),
                      ),
                    ),
                  ),
                // 内容：水平铺满、高度严格随内容自适应（不强制撑满整块玻璃）。
                // 用直接 SizedBox 而非 Align 作非定位子节点：Stack 高度 = 内容高度，
                // 避免下拉面板在宽触发框下被 Align 撑大而出现「底部空白比顶部大」。
                SizedBox(
                  width: double.infinity,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃「激活胶囊 / 胶囊滑块」装饰
///
/// 对应底部导航栏的激活块：半透明白背景 + 白色描边 + 白色发光 + 下沉阴影。
class GlassCapsuleDecoration {
  static BoxDecoration build(AppColorScheme colors, double radius,
      {bool strong = false}) {
    final isDark = colors.isDark;
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: strong ? 0.2 : 0.16)
          : Colors.white.withValues(alpha: strong ? 0.95 : 0.9),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: strong ? 0.32 : 0.28)
            : Colors.white.withValues(alpha: 0.8),
        width: 1,
      ),
      boxShadow: [
        // 白色发光：与 tabbar 激活块一致（0.6 / 12 / 1），统一发光强度
        BoxShadow(
          color: Colors.white.withValues(alpha: strong ? 0.75 : 0.6),
          blurRadius: strong ? 18 : 12,
          spreadRadius: strong ? 2.5 : 1,
        ),
        // 下沉投影：增强立体感（与 tabbar 激活块一致）
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}