import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// 网络工具类
class NetworkUtils {
  NetworkUtils._();

  static final NetworkInfo _networkInfo = NetworkInfo();

  /// 获取本机 IP 地址
  static Future<String?> getLocalIp() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      debugPrint('[NetworkUtils] getWifiIP() = $ip');
      return ip;
    } catch (e) {
      debugPrint('[NetworkUtils] getWifiIP() 失败: $e');
      return null;
    }
  }

  /// 获取本机设备名称
  static String getDeviceName() {
    if (kIsWeb) return 'Web 设备';
    return Platform.localHostname;
  }

  /// 基于本机 IP 计算子网广播地址（假定 /24 掩码，多数家用 LAN 成立）
  static Future<String> getSubnetBroadcastAddress() async {
    final ip = await getLocalIp();
    if (ip == null) {
      debugPrint('[NetworkUtils] 本机 IP 为空，使用 255.255.255.255 有限广播地址');
      return '255.255.255.255';
    }
    final parts = ip.split('.');
    if (parts.length != 4) {
      debugPrint('[NetworkUtils] IP 格式异常: $ip，使用 255.255.255.255');
      return '255.255.255.255';
    }
    parts[3] = '255';
    final broadcast = parts.join('.');
    debugPrint('[NetworkUtils] 本机 IP=$ip → 子网广播地址=$broadcast');
    return broadcast;
  }
}
