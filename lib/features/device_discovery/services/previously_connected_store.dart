import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/global_providers.dart';
import '../models/device.dart';

/// 持久化"已连接过设备"列表
class PreviouslyConnectedStore {
  final SharedPreferences _prefs;

  PreviouslyConnectedStore(this._prefs);

  /// 读取持久化设备列表（不含 ip/online）
  List<Device> list() {
    final raw = _prefs.getString(StorageKeys.previouslyConnectedDevices);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr
          .map((e) {
            final map = e as Map<String, dynamic>;
            return Device.fromJson(map);
          })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 读取缓存的密码
  String? getPassword(String deviceId) {
    final devices = list();
    for (final d in devices) {
      if (d.id == deviceId) {
        final raw = _prefs.getString(StorageKeys.previouslyConnectedDevices);
        if (raw == null) return null;
        try {
          final arr = jsonDecode(raw) as List<dynamic>;
          for (final e in arr) {
            final map = e as Map<String, dynamic>;
            if (map['id'] == deviceId) {
              return map['password'] as String?;
            }
          }
        } catch (_) {}
        return null;
      }
    }
    return null;
  }

  /// 成功连接后调用
  void add(Device device, {String? password}) {
    final current = _loadRaw();
    // 移除同 ID 旧记录
    current.removeWhere((e) => e['id'] == device.id);
    final entry = device.toJson();
    if (password != null && password.isNotEmpty) {
      entry['password'] = password;
    }
    current.add(entry);
    _saveRaw(current);
  }

  /// 用户手动移除
  void remove(String deviceId) {
    final current = _loadRaw();
    current.removeWhere((e) => e['id'] == deviceId);
    _saveRaw(current);
  }

  /// 更新密码
  void updatePassword(String deviceId, String pwd) {
    final current = _loadRaw();
    for (final e in current) {
      if (e['id'] == deviceId) {
        if (pwd.isEmpty) {
          e.remove('password');
        } else {
          e['password'] = pwd;
        }
        break;
      }
    }
    _saveRaw(current);
  }

  List<Map<String, dynamic>> _loadRaw() {
    final raw = _prefs.getString(StorageKeys.previouslyConnectedDevices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  void _saveRaw(List<Map<String, dynamic>> data) {
    _prefs.setString(
      StorageKeys.previouslyConnectedDevices,
      jsonEncode(data),
    );
  }
}
