import 'package:flutter/material.dart';

/// 文件类型枚举
enum FileContentType {
  image,
  video,
  audio,
  text,
  word,
  excel,
  ppt,
  pdf,
  archive,
  apk,
  code,
  other,
}

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

  // ---- 文件类型判断 ----

  static const _imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic'];
  static const _videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'rmvb', 'ts', '3gp'];
  static const _audioExts = ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'];
  static const _textExts = ['txt', 'md', 'log', 'csv', 'rtf'];
  static const _wordExts = ['doc', 'docx'];
  static const _excelExts = ['xls', 'xlsx', 'csv'];
  static const _pptExts = ['ppt', 'pptx'];
  static const _pdfExts = ['pdf'];
  static const _archiveExts = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'];
  static const _apkExts = ['apk', 'xapk'];
  static const _codeExts = ['dart', 'java', 'kt', 'py', 'js', 'ts', 'html', 'css', 'json', 'xml', 'yaml', 'yml', 'c', 'cpp', 'h', 'go', 'rs', 'rb', 'php', 'sh'];

  bool get isImage => _imageExts.contains(extension);
  bool get isVideo => _videoExts.contains(extension);
  bool get isAudio => _audioExts.contains(extension);
  bool get isText => _textExts.contains(extension);
  bool get isWord => _wordExts.contains(extension);
  bool get isExcel => _excelExts.contains(extension);
  bool get isPpt => _pptExts.contains(extension);
  bool get isPdf => _pdfExts.contains(extension);
  bool get isArchive => _archiveExts.contains(extension);
  bool get isApk => _apkExts.contains(extension);
  bool get isCode => _codeExts.contains(extension);

  /// 获取文件内容类型
  FileContentType get contentType {
    if (isDirectory) return FileContentType.other;
    if (isImage) return FileContentType.image;
    if (isVideo) return FileContentType.video;
    if (isAudio) return FileContentType.audio;
    if (isText) return FileContentType.text;
    if (isWord) return FileContentType.word;
    if (isExcel) return FileContentType.excel;
    if (isPpt) return FileContentType.ppt;
    if (isPdf) return FileContentType.pdf;
    if (isArchive) return FileContentType.archive;
    if (isApk) return FileContentType.apk;
    if (isCode) return FileContentType.code;
    return FileContentType.other;
  }

  /// 获取文件类型对应的图标
  IconData get typeIcon {
    if (isDirectory) return Icons.folder;
    return switch (contentType) {
      FileContentType.image => Icons.image,
      FileContentType.video => Icons.video_file,
      FileContentType.audio => Icons.audio_file,
      FileContentType.text => Icons.description,
      FileContentType.word => Icons.description,
      FileContentType.excel => Icons.table_chart,
      FileContentType.ppt => Icons.slideshow,
      FileContentType.pdf => Icons.picture_as_pdf,
      FileContentType.archive => Icons.folder_zip,
      FileContentType.apk => Icons.android,
      FileContentType.code => Icons.code,
      FileContentType.other => Icons.insert_drive_file,
    };
  }

  /// 获取文件类型对应的颜色
  Color get typeColor {
    return switch (contentType) {
      FileContentType.image => Colors.redAccent,
      FileContentType.video => Colors.teal,
      FileContentType.audio => Colors.purple,
      FileContentType.text => Colors.amber,
      FileContentType.word => Colors.blue,
      FileContentType.excel => Colors.green,
      FileContentType.ppt => Colors.orange,
      FileContentType.pdf => Colors.red,
      FileContentType.archive => Colors.brown,
      FileContentType.apk => Colors.lightGreen,
      FileContentType.code => Colors.indigo,
      FileContentType.other => Colors.blueGrey,
    };
  }

  /// 是否有可显示的封面（图片或视频）
  bool get hasCover => isImage || isVideo;

  /// 文件唯一标识（路径 + 大小 + 修改时间）
  String get uniqueKey => '$path|${size ?? 0}|${modifiedAt?.millisecondsSinceEpoch ?? 0}';

  /// 格式化文件大小
  String get formattedSize {
    if (size == null) return '--';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 格式化修改时间
  String get formattedDate {
    if (modifiedAt == null) return '--';
    return '${modifiedAt!.year}-${modifiedAt!.month.toString().padLeft(2, '0')}-${modifiedAt!.day.toString().padLeft(2, '0')}';
  }
}
