import '../../../core/services/device_info_service.dart';

/// 设备连接状态
enum DeviceConnectionState {
  /// 未连接（附近设备 / 已断开）
  unconnected,

  /// 连接中（握手 / 密码验证中）
  connecting,

  /// 已连接（WebSocket 已建立）
  connected,
}

/// 已发现/已连接的设备模型
class Device {
  /// 永久唯一 ID（对端 SharedPreferences 中的 UUID）
  final String id;

  /// 设备显示名称（来自对端 beacon）
  final String name;

  /// 当前 IP（可变，每次广播可能不同）
  final String ip;

  /// 设备类型图标（来自对端 beacon，作为"头像"）
  final DeviceTypeIcon typeIcon;

  /// 是否在线（基于 beacon 心跳超时判定）
  final bool isOnline;

  /// 当前连接状态
  final DeviceConnectionState connectionState;

  /// 对端是否启用了连接密码
  final bool hasPassword;

  /// 最后一次收到该设备 beacon 的时间戳（ms）
  final int lastSeenAt;

  const Device({
    required this.id,
    required this.name,
    required this.ip,
    required this.typeIcon,
    this.isOnline = true,
    this.connectionState = DeviceConnectionState.unconnected,
    this.hasPassword = false,
    this.lastSeenAt = 0,
  });

  Device copyWith({
    String? id,
    String? name,
    String? ip,
    DeviceTypeIcon? typeIcon,
    bool? isOnline,
    DeviceConnectionState? connectionState,
    bool? hasPassword,
    int? lastSeenAt,
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    ip: ip ?? this.ip,
    typeIcon: typeIcon ?? this.typeIcon,
    isOnline: isOnline ?? this.isOnline,
    connectionState: connectionState ?? this.connectionState,
    hasPassword: hasPassword ?? this.hasPassword,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  /// 用于持久化的 JSON 序列化（仅稳定字段，不含 ip/online/connectionState/lastSeenAt）
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'typeIcon': typeIcon.name,
    'hasPassword': hasPassword,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    typeIcon: DeviceTypeIcon.values.byName(json['typeIcon'] as String),
    hasPassword: (json['hasPassword'] as bool?) ?? false,
    ip: '',
    isOnline: false,
  );
}
