import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';

/// 当前选中的设备
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, String?>(
      SelectedDeviceNotifier.new,
    );

class SelectedDeviceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  set device(String? value) => state = value;
}

/// 当前路径
final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '/';

  set path(String value) => state = value;
}

/// 文件分类筛选
final fileCategoryProvider = NotifierProvider<FileCategoryNotifier, String>(
  FileCategoryNotifier.new,
);

class FileCategoryNotifier extends Notifier<String> {
  @override
  String build() => '图片';

  set category(String value) => state = value;
}

/// 文件列表
final fileListProvider = NotifierProvider<FileListNotifier, List<FileItem>>(
  FileListNotifier.new,
);

class FileListNotifier extends Notifier<List<FileItem>> {
  @override
  List<FileItem> build() {
    // TODO: 从 SMB 连接获取真实文件列表
    return const [
      FileItem(name: '风景.jpg', path: '/风景.jpg'),
      FileItem(name: '截图.png', path: '/截图.png'),
      FileItem(name: '头像.jpg', path: '/头像.jpg'),
      FileItem(name: '设计稿.png', path: '/设计稿.png'),
      FileItem(name: '壁纸.jpg', path: '/壁纸.jpg'),
      FileItem(name: '相册1.jpg', path: '/相册1.jpg'),
    ];
  }

  set files(List<FileItem> value) => state = value;
}
