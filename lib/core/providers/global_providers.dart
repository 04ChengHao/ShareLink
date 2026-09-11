import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_info_service.dart';
import '../services/storage_service.dart';
import '../utils/uuid_generator.dart';

// =============================================================================
// 存储键名常量
// =============================================================================
class StorageKeys {
  StorageKeys._();

  static const themePreference = 'theme_preference';
  static const connectionEnabled = 'connection_enabled';
  static const acceptConnections = 'accept_connections';
  static const usePassword = 'use_password';
  static const connectionPassword = 'connection_password';
  static const clipboardSync = 'clipboard_sync';
  static const sharedAlbum = 'shared_album';
  static const sharedFolder = 'shared_folder';
  static const sharedContent = 'shared_content';
  static const deviceId = 'device_id';
  static const previouslyConnectedDevices = 'previously_connected_devices';
  static const customCategories = 'custom_categories';
  static const filterShowFileName = 'filter_show_file_name';
  static const filterTimelineGroup = 'filter_timeline_group';
  static const filterExtensionGroup = 'filter_extension_group';
  static const filterSortAscending = 'filter_sort_ascending';
  static const filterOnlyDownloaded = 'filter_only_downloaded';
  static const desktopColumnMode = 'desktop_column_mode';
  static const mobileCategoryDisplayMode = 'mobile_category_display_mode';
  static const downloads = 'downloads_registry';
  static const mediaDurations = 'media_durations';
}

// =============================================================================
// 主题模式
// =============================================================================

/// 应用主题模式
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.read(sharedPrefsProvider);
    final stored = prefs.getString(StorageKeys.themePreference) ?? 'system';
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  set mode(ThemeMode value) => state = value;
}

/// 深色模式偏好（用于设置页下拉框）
final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );

enum ThemePreference { system, light, dark }

class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  @override
  ThemePreference build() {
    final prefs = ref.read(sharedPrefsProvider);
    final stored = prefs.getString(StorageKeys.themePreference) ?? 'system';
    return switch (stored) {
      'light' => ThemePreference.light,
      'dark' => ThemePreference.dark,
      _ => ThemePreference.system,
    };
  }

  set preference(ThemePreference value) {
    state = value;
    // 持久化
    ref
        .read(sharedPrefsProvider)
        .setString(StorageKeys.themePreference, value.name);
    // 同步主题模式
    ref.read(themeModeProvider.notifier).mode = switch (value) {
      ThemePreference.system => ThemeMode.system,
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
    };
  }
}

// =============================================================================
// 设备信息
// =============================================================================

/// 本机唯一设备 ID（首次生成 UUID 并持久化）
final localDeviceIdProvider = Provider<String>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  var id = prefs.getString(StorageKeys.deviceId);
  if (id == null) {
    id = generateUuidV4();
    prefs.setString(StorageKeys.deviceId, id);
  }
  return id;
});

/// 当前设备信息（真实设备名称、型号、类型图标）
final deviceInfoProvider = FutureProvider<DeviceInfo>(
  (ref) => DeviceInfoService.getDeviceInfo(),
);

/// 当前设备显示名称
final deviceNameProvider = Provider<String>((ref) {
  final info = ref.watch(deviceInfoProvider);
  return info.maybeWhen(data: (d) => d.name, orElse: () => '正在获取设备信息…');
});

// =============================================================================
// 连接设置
// =============================================================================

/// 是否接受其他设备连接
final acceptConnectionsProvider =
    NotifierProvider<AcceptConnectionsNotifier, bool>(
      AcceptConnectionsNotifier.new,
    );

class AcceptConnectionsNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref
            .read(sharedPrefsProvider)
            .getBool(StorageKeys.acceptConnections) ??
        true;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.acceptConnections, value);
  }
}

/// 是否启用连接密码
final usePasswordProvider = NotifierProvider<UsePasswordNotifier, bool>(
  UsePasswordNotifier.new,
);

class UsePasswordNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPrefsProvider).getBool(StorageKeys.usePassword) ??
        false;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.usePassword, value);
  }
}

/// 连接密码
final connectionPasswordProvider =
    NotifierProvider<ConnectionPasswordNotifier, String>(
      ConnectionPasswordNotifier.new,
    );

class ConnectionPasswordNotifier extends Notifier<String> {
  @override
  String build() {
    return ref
            .read(sharedPrefsProvider)
            .getString(StorageKeys.connectionPassword) ??
        '';
  }

  set password(String value) {
    state = value;
    ref
        .read(sharedPrefsProvider)
        .setString(StorageKeys.connectionPassword, value);
  }
}

/// 是否共享剪贴板
final clipboardSyncProvider = NotifierProvider<ClipboardSyncNotifier, bool>(
  ClipboardSyncNotifier.new,
);

class ClipboardSyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPrefsProvider).getBool(StorageKeys.clipboardSync) ??
        true;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.clipboardSync, value);
  }
}
