import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/global_providers.dart';
import '../../../core/services/storage_service.dart';

/// 共享相册
final sharedAlbumProvider = NotifierProvider<SharedAlbumNotifier, bool>(
  SharedAlbumNotifier.new,
);

class SharedAlbumNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPrefsProvider).getBool(StorageKeys.sharedAlbum) ??
        true;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.sharedAlbum, value);
  }
}

/// 共享文件夹
final sharedFolderProvider = NotifierProvider<SharedFolderNotifier, bool>(
  SharedFolderNotifier.new,
);

class SharedFolderNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPrefsProvider).getBool(StorageKeys.sharedFolder) ??
        false;
  }

  set enabled(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(StorageKeys.sharedFolder, value);
  }
}

/// 设置页当前子标签
final settingsTabProvider = NotifierProvider<SettingsTabNotifier, String>(
  SettingsTabNotifier.new,
);

class SettingsTabNotifier extends Notifier<String> {
  @override
  String build() => 'general';

  set tab(String value) => state = value;
}