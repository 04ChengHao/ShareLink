import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 新拟物（Neuomorphic）光照阴影工具
///
/// 左上白色高光 + 右下深色阴影，营造立体光照质感。
class NeuomorphicStyle {
  NeuomorphicStyle._();

  /// 浅色模式下的卡片光照阴影
  static List<BoxShadow> light({
    double blur = 12,
    double spread = 0,
    Color? baseColor,
  }) {
    return [
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.9),
        offset: Offset(-blur / 3, -blur / 3),
        blurRadius: blur,
        spreadRadius: spread,
      ),
      BoxShadow(
        color: (baseColor ?? const Color(0xFFB0C4DE)).withValues(alpha: 0.45),
        offset: Offset(blur / 3, blur / 3),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }

  /// 深色模式下的卡片光照阴影
  static List<BoxShadow> dark({double blur = 12, double spread = 0}) {
    return [
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.05),
        offset: Offset(-blur / 3, -blur / 3),
        blurRadius: blur,
        spreadRadius: spread,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.5),
        offset: Offset(blur / 3, blur / 3),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }

  /// 根据当前亮度自动选择
  static List<BoxShadow> adaptive(
    Brightness brightness, {
    double blur = 12,
    double spread = 0,
  }) {
    return brightness == Brightness.dark
        ? dark(blur: blur, spread: spread)
        : light(blur: blur, spread: spread);
  }

  /// 通过 [AppColorScheme] 获取阴影
  static List<BoxShadow> of(AppColorScheme colors, {double blur = 12}) {
    return [
      BoxShadow(
        color: colors.neuHighlight,
        offset: Offset(-blur / 3, -blur / 3),
        blurRadius: blur,
      ),
      BoxShadow(
        color: colors.neuShadow,
        offset: Offset(blur / 3, blur / 3),
        blurRadius: blur,
      ),
    ];
  }
}
