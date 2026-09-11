import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// 在系统文件管理器中打开指定目录（或选中指定文件）
  ///
  /// - Windows：explorer /select, 定位文件所在文件夹
  /// - macOS：open -R 在访达中显示文件
  /// - Linux：xdg-open 打开所在目录
  /// - 移动端：尽力通过系统应用打开
  static Future<void> openInSystem(String path) async {
    if (kIsWeb) return;
    try {
      final exists = File(path).existsSync() || Directory(path).existsSync();
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final dir = File(path).existsSync() ? File(path).parent.path : path;
        await Process.run('xdg-open', [dir]);
      } else {
        if (exists) await OpenFilex.open(path);
      }
    } catch (e) {
      debugPrint('[PlatformUtils] 在系统管理中打开失败: $e');
    }
  }

  /// 在系统文件管理器中打开指定的**文件夹**
  ///
  /// 统一使用 [url_launcher] 唤起系统应用（Actual Uri 交系统处理）：
  /// - Android：构造安全访问（SAF）的 `content://` 文档 URI，唤起系统文件应用；
  ///   无应用可处理时回退 [openInSystem]。个别 ROM 可能只打开下载根目录。
  /// - 桌面：用 `file:` URI + 外部应用模式打开资源管理器/访达
  /// - iOS：尽力用系统文件应用打开，失败静默（iOS 对任意目录访问受限）
  static Future<void> openFolder(String folderPath) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _openFolderAndroidWithLauncher(folderPath);
      } else {
        // Windows / macOS / Linux / iOS 统一用 file: 协议唤起系统应用
        await launchUrl(
          Uri.directory(folderPath),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('[PlatformUtils] 打开文件夹失败: $e');
    }
  }

  /// 将绝对路径转成 SAF 的 content:// 文档 URI（供 url_launcher 使用）
  ///
  /// `/storage/emulated/0/Download/someDir`
  /// -> `content://com.android.externalstorage.documents/document/primary:Download/someDir`
  static String _androidFolderContentUri(String path) {
    String relative;
    const root = '/storage/emulated/0';
    if (path.startsWith(root)) {
      relative = path.substring(root.length).replaceFirst(RegExp(r'^/+'), '');
    } else {
      final m = RegExp(r'^/storage/([A-Za-z0-9-]+)/(.*)$').firstMatch(path);
      relative = m != null ? '${m.group(1)}:${m.group(2)}' : path;
    }
    final docId = Uri.encodeComponent('primary:$relative');
    return 'content://com.android.externalstorage.documents/document/$docId';
  }

  /// Android 打开文件夹：url_launcher 唤起系统文件应用，失败回退
  static Future<void> _openFolderAndroidWithLauncher(String folderPath) async {
    final uri = _androidFolderContentUri(folderPath);
    try {
      final ok = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!ok) {
        debugPrint('[PlatformUtils] 无应用可打开 $uri，回退系统选择器');
        await openInSystem(folderPath);
      }
    } catch (e) {
      debugPrint('[PlatformUtils] url_launcher 打开文件夹失败，回退系统选择器: $e');
      await openInSystem(folderPath);
    }
  }
}
