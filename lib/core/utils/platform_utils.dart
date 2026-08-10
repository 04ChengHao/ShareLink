import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台工具类
class PlatformUtils {
  PlatformUtils._();

  /// 是否为桌面端（Windows / macOS / Linux）
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 是否为移动端（Android / iOS）
  static bool get isMobile {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 是否为 Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// 是否为 macOS
  static bool get isMacOS {
    if (kIsWeb) return false;
    return Platform.isMacOS;
  }

  /// 是否为 Linux
  static bool get isLinux {
    if (kIsWeb) return false;
    return Platform.isLinux;
  }

  /// 获取平台对应的系统字体族
  ///
  /// Windows 默认使用微软雅黑，避免 Flutter 默认字体在中文环境下
  /// 出现字重不一致（部分字粗、部分字细）和繁体异字问题。
  /// macOS 使用苹方，其余平台返回 null 走系统默认。
  static String? get systemFontFamily {
    if (kIsWeb) return null;
    if (Platform.isWindows) return 'Microsoft YaHei';
    if (Platform.isMacOS) return 'PingFang SC';
    return null;
  }
}
