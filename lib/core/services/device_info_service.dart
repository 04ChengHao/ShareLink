import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// 设备信息描述
class DeviceInfo {
  /// 设备显示名称
  final String name;

  /// 设备型号（手机端为型号，桌面端为主机名）
  final String model;

  /// 设备类型图标
  final DeviceTypeIcon typeIcon;

  const DeviceInfo({
    required this.name,
    required this.model,
    required this.typeIcon,
  });
}

/// 设备类型图标枚举
enum DeviceTypeIcon { windows, mac, linux, android, ios, web }

/// 设备信息服务：读取真实设备名称和型号
class DeviceInfoService {
  DeviceInfoService._();

  static final _plugin = DeviceInfoPlugin();

  /// 获取当前设备信息
  static Future<DeviceInfo> getDeviceInfo() async {
    if (kIsWeb) {
      final webInfo = await _plugin.webBrowserInfo;
      return DeviceInfo(
        name: 'Web 设备',
        model: webInfo.browserName.name,
        typeIcon: DeviceTypeIcon.web,
      );
    }

    if (Platform.isWindows) {
      final info = await _plugin.windowsInfo;
      return DeviceInfo(
        name: info.computerName,
        model: info.computerName,
        typeIcon: DeviceTypeIcon.windows,
      );
    }

    if (Platform.isMacOS) {
      final info = await _plugin.macOsInfo;
      return DeviceInfo(
        name: info.computerName,
        model: info.model,
        typeIcon: DeviceTypeIcon.mac,
      );
    }

    if (Platform.isLinux) {
      final info = await _plugin.linuxInfo;
      return DeviceInfo(
        name: info.name,
        model: info.name,
        typeIcon: DeviceTypeIcon.linux,
      );
    }

    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;
      return DeviceInfo(
        name: _androidDeviceName(info.model),
        model: info.model,
        typeIcon: DeviceTypeIcon.android,
      );
    }

    if (Platform.isIOS) {
      final info = await _plugin.iosInfo;
      return DeviceInfo(
        name: _iosDeviceName(info.utsname.machine),
        model: info.utsname.machine,
        typeIcon: DeviceTypeIcon.ios,
      );
    }

    return const DeviceInfo(
      name: '未知设备',
      model: 'Unknown',
      typeIcon: DeviceTypeIcon.web,
    );
  }

  /// iOS 机器型号标识转可读名称
  static String _iosDeviceName(String machine) {
    const mapping = <String, String>{
      'iPhone15,2': 'iPhone 14 Pro',
      'iPhone15,3': 'iPhone 14 Pro Max',
      'iPhone15,4': 'iPhone 15',
      'iPhone15,5': 'iPhone 15 Plus',
      'iPhone16,1': 'iPhone 15 Pro',
      'iPhone16,2': 'iPhone 15 Pro Max',
      'iPhone17,1': 'iPhone 16 Pro',
      'iPhone17,2': 'iPhone 16 Pro Max',
      'iPhone17,3': 'iPhone 16',
      'iPhone17,4': 'iPhone 16 Plus',
      'iPad13,1': 'iPad Air (4th gen)',
      'iPad13,2': 'iPad Air (4th gen)',
      'iPad14,1': 'iPad mini (6th gen)',
      'iPad14,2': 'iPad mini (6th gen)',
    };
    return mapping[machine] ?? machine;
  }

  /// Android 型号转可读名称
  static String _androidDeviceName(String model) {
    return model;
  }
}
