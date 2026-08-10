import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clipboard_item.dart';

/// 剪贴板历史列表
final clipboardHistoryProvider =
    NotifierProvider<ClipboardHistoryNotifier, List<ClipboardItem>>(
  ClipboardHistoryNotifier.new,
);

class ClipboardHistoryNotifier extends Notifier<List<ClipboardItem>> {
  @override
  List<ClipboardItem> build() {
    // TODO: 从本地数据库或 WebSocket 同步获取
    return const [];
  }

  set history(List<ClipboardItem> value) => state = value;

  void add(ClipboardItem item) => state = [...state, item];
}

/// 是否启用自动同步
final clipboardAutoSyncProvider =
    NotifierProvider<ClipboardAutoSyncNotifier, bool>(
  ClipboardAutoSyncNotifier.new,
);

class ClipboardAutoSyncNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  set enabled(bool value) => state = value;
}
