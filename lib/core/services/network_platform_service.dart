import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 网络平台通道服务
///
/// 负责以下原生操作：
/// - 获取/释放 MulticastLock（接收 UDP 广播必须）
/// - 请求 ACCESS_FINE_LOCATION 运行时权限（Android 12+ 获取 WiFi IP 必须）
class NetworkPlatformService {
  NetworkPlatformService._();

  static const _channel = MethodChannel('com.sharelink.app/network');

  /// 是否为 Android 平台
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 获取 Android SDK 版本
  static Future<int> getSdkInt() async {
    if (!isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>('getSdkInt') ?? 0;
    } catch (e) {
      debugPrint('[NetworkPlatform] getSdkInt 失败: $e');
      return 0;
    }
  }

  /// 请求位置权限（Android 12+ 获取 WiFi IP 需要）
  ///
  /// 返回 true 表示已授权
  static Future<bool> requestLocationPermission() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestLocationPermission');
      debugPrint('[NetworkPlatform] 位置权限请求结果: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[NetworkPlatform] 请求位置权限失败: $e');
      return false;
    }
  }

  /// 检查是否已拥有位置权限
  static Future<bool> hasLocationPermission() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasLocationPermission') ?? false;
    } catch (e) {
      debugPrint('[NetworkPlatform] 检查位置权限失败: $e');
      return false;
    }
  }

  /// 获取 MulticastLock（接收 UDP 广播必须）
  ///
  /// Android WiFi 驱动默认过滤广播/多播包，
  /// 不持有 MulticastLock 时 RawDatagramSocket 收不到 UDP 广播。
  static Future<void> acquireMulticastLock() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('acquireMulticastLock');
      debugPrint('[NetworkPlatform] MulticastLock 已获取');
    } catch (e) {
      debugPrint('[NetworkPlatform] 获取 MulticastLock 失败: $e');
    }
  }

  /// 释放 MulticastLock
  static Future<void> releaseMulticastLock() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('releaseMulticastLock');
      debugPrint('[NetworkPlatform] MulticastLock 已释放');
    } catch (e) {
      debugPrint('[NetworkPlatform] 释放 MulticastLock 失败: $e');
    }
  }
}
