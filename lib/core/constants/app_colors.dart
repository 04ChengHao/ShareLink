import 'package:flutter/material.dart';

/// 应用颜色常量（静态基础值）
class AppColors {
  AppColors._();

  // 主色调
  static const Color primary = Color(0xFF007AFF);
  static const Color primaryLight = Color(0xFF5AC8FA);
  static const Color accent = Color(0xFF34C759);

  // 状态
  static const Color online = accent;
  static const Color offline = Color(0xFFC7C7CC);
}

/// 主题感知的颜色方案
///
/// 根据亮色/深色模式提供统一的颜色访问入口，避免散落各处的硬编码颜色。
class AppColorScheme {
  final Brightness brightness;

  AppColorScheme(this.brightness);

  bool get isDark => brightness == Brightness.dark;

  /// 获取当前上下文的颜色方案
  static AppColorScheme of(BuildContext context) {
    return AppColorScheme(Theme.brightnessOf(context));
  }

  // ---- 背景 ----
  /// 页面背景
  Color get scaffoldBg =>
      isDark ? const Color(0xFF121214) : const Color(0xFFE6F2FF);

  /// 卡片/面板背景
  Color get cardBg => isDark ? const Color(0xFF1E1E22) : Colors.white;

  /// 玻璃容器背景
  Color get glassBg => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.65);

  /// 玻璃容器边框
  Color get glassBorder => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.6);

  // ---- 文字 ----
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF1C1C1E);

  Color get textSecondary =>
      isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF8E8E93);

  Color get textHint =>
      isDark ? Colors.white.withValues(alpha: 0.35) : const Color(0xFFC7C7CC);

  // ---- 图标 ----
  Color get iconPrimary =>
      isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1C1C1E);

  Color get iconSecondary =>
      isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF8E8E93);

  Color get iconActive => AppColors.primary;

  // ---- 分割线 ----
  Color get divider => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);

  // ---- 拟物阴影 ----
  /// 拟物高光色（左上）
  Color get neuHighlight =>
      isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;

  /// 拟物阴影色（右下）
  Color get neuShadow => isDark
      ? Colors.black.withValues(alpha: 0.5)
      : const Color(0xFFB0C4DE).withValues(alpha: 0.45);

  // ---- 输入控件 ----
  /// 输入控件背景（在卡片上可见）
  Color get inputBg => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFF2F2F7);

  /// 输入控件边框（在卡片上可见）
  Color get inputBorder => isDark
      ? Colors.white.withValues(alpha: 0.15)
      : const Color(0xFFD1D1D6);

  // ---- 主色变体 ----
  Color primaryWithAlpha(double alpha) =>
      AppColors.primary.withValues(alpha: alpha);

  Color accentWithAlpha(double alpha) =>
      AppColors.accent.withValues(alpha: alpha);
}
