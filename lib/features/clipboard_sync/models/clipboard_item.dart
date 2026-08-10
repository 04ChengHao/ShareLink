/// 剪贴板历史条目
class ClipboardItem {
  final String id;
  final String content;
  final String deviceName;
  final DateTime createdAt;

  const ClipboardItem({
    required this.id,
    required this.content,
    required this.deviceName,
    required this.createdAt,
  });
}
