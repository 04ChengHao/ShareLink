import 'package:flutter/material.dart';

import '../services/device_info_service.dart';

/// 设备类型 → 图标映射（公共工具，供 DeviceListItem 和 Settings 共用）
IconData deviceTypeIcon(DeviceTypeIcon? type) => switch (type) {
  DeviceTypeIcon.windows => Icons.desktop_windows,
  DeviceTypeIcon.mac => Icons.laptop_mac,
  DeviceTypeIcon.linux => Icons.computer,
  DeviceTypeIcon.android => Icons.android,
  DeviceTypeIcon.ios => Icons.phone_iphone,
  DeviceTypeIcon.web => Icons.language,
  null => Icons.devices,
};
