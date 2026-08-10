import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'neuomorphic_style.dart';

/// 新拟物卡片容器
///
/// 左上亮、右下暗的光照感。可配置是否可点击（带水波纹反馈）。
class NeuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const NeuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 14,
    this.blur = 10,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.cardBg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: NeuomorphicStyle.adaptive(theme.brightness, blur: blur),
      ),
      child: onTap == null
          ? child
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: child,
              ),
            ),
    );
  }
}
