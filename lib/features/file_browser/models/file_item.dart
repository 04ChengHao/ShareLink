/// 文件或文件夹实体
class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;

  const FileItem({
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.size,
    this.modifiedAt,
  });

  String get extension {
    final index = name.lastIndexOf('.');
    return index > 0 ? name.substring(index + 1).toLowerCase() : '';
  }

  bool get isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension);
  bool get isVideo => ['mp4', 'mkv', 'avi', 'mov', 'wmv'].contains(extension);
  bool get isText => ['txt', 'md', 'log'].contains(extension);
}
