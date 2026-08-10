import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'neuomorphic_style.dart';

/// 玻璃拟态卡片
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.glassBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: colors.glassBorder),
        boxShadow: NeuomorphicStyle.adaptive(theme.brightness, blur: 32),
      ),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return content;
  }
}
