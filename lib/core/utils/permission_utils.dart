import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限工具类
///
/// 处理 Android 平台的文件访问权限：
/// - Android 13+：细粒度媒体权限（READ_MEDIA_IMAGES/AUDIO/VIDEO）
/// - Android 11-12：READ_EXTERNAL_STORAGE
/// - Android 11+：MANAGE_EXTERNAL_STORAGE（访问文档/下载等非媒体文件）
class PermissionUtils {
  PermissionUtils._();

  static final _plugin = DeviceInfoPlugin();

  /// 获取 Android SDK 版本（非 Android 平台返回 0）
  static Future<int> get _androidSdkInt async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    final info = await _plugin.androidInfo;
    return info.version.sdkInt;
  }

  /// 请求所有文件访问权限（MANAGE_EXTERNAL_STORAGE）
  ///
  /// Android 11+ 访问 Documents/Download 等目录下的非媒体文件（PDF/APK/DAT 等）必需。
  /// 该权限无法通过普通弹窗授予，必须跳转到系统设置页让用户手动开启。
  ///
  /// 返回值：
  /// - true：已授权（或 Android 10 及以下不需要）
  /// - false：未授权
  static Future<bool> requestAllFilesAccess() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final sdk = await _androidSdkInt;

    // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE
    if (sdk >= 30) {
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;

      // 请求权限（会跳转系统设置页）
      final result = await Permission.manageExternalStorage.request();
      return result.isGranted;
    }

    // Android 10 及以下：使用传统存储权限
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final result = await Permission.storage.request();
    return result.isGranted;
  }

  /// 检查所有文件访问权限是否已授予（不请求）
  static Future<bool> hasAllFilesAccess() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final sdk = await _androidSdkInt;
    if (sdk >= 30) {
      return Permission.manageExternalStorage.status.isGranted;
    }
    return Permission.storage.status.isGranted;
  }

  /// 跳转到系统应用设置页（引导用户手动授权）
  static Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }
}
