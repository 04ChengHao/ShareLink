import 'package:flutter/material.dart';

import 'file_item.dart';

/// 可选分类图标调色板。
///
/// 必须全部为 const 实例：`FileCategory.fromJson` 需要按 codePoint 还原图标，
/// 若在运行时构造 `IconData`（非 const），release 构建的图标字体
/// tree-shaking 会直接失败（"Avoid non-constant invocations of IconData"）。
const List<IconData> categoryIcons = [
  Icons.image, Icons.video_file, Icons.audio_file, Icons.description,
  Icons.table_chart, Icons.slideshow, Icons.picture_as_pdf,
  Icons.folder_zip, Icons.code, Icons.android, Icons.folder,
  Icons.photo_library, Icons.movie, Icons.music_note, Icons.book,
  Icons.archive, Icons.insert_drive_file, Icons.folder_open,
  Icons.work, Icons.school, Icons.business, Icons.home,
  Icons.star, Icons.favorite, Icons.lightbulb, Icons.flight,
  Icons.shopping_bag, Icons.sports, Icons.restaurant, Icons.pets,
  Icons.computer, Icons.phone, Icons.tablet, Icons.watch,
  Icons.camera, Icons.headphones, Icons.gamepad, Icons.newspaper,
];

/// 文件分类模型
class FileCategory {
  final String name;
  final IconData icon;
  final List<String> fileTypes;
  final bool selectAll;

  const FileCategory({
    required this.name,
    required this.icon,
    this.fileTypes = const [],
    this.selectAll = false,
  });

  FileCategory copyWith({
    String? name,
    IconData? icon,
    List<String>? fileTypes,
    bool? selectAll,
  }) {
    return FileCategory(
      name: name ?? this.name,
      icon: icon ?? this.icon,
      fileTypes: fileTypes ?? this.fileTypes,
      selectAll: selectAll ?? this.selectAll,
    );
  }

  /// 判断文件是否属于此分类
  bool matches(FileItem file) {
    if (selectAll) return true;
    if (file.isDirectory) return false;
    return fileTypes.any((ext) => ext.toLowerCase() == file.extension);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'iconCodePoint': icon.codePoint,
        'fileTypes': fileTypes,
        'selectAll': selectAll,
      };

  factory FileCategory.fromJson(Map<String, dynamic> json) {
    final codePoint = json['iconCodePoint'] as int? ?? 0xe318; // Icons.folder
    // IconData 构造函数是 const，但 codePoint 是运行时值
    // 通过 switch 映射常见图标避免 warning
    final icon = _mapIconCodePoint(codePoint);
    return FileCategory(
      name: json['name'] as String? ?? '',
      icon: icon,
      fileTypes: (json['fileTypes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      selectAll: json['selectAll'] as bool? ?? false,
    );
  }

  /// 将 iconCodePoint 映射回 IconData。
  ///
  /// 从 const 调色板 [categoryIcons] 中查找，保证返回的都是 const 实例，
  /// 使 release 构建仍可对图标字体做 tree-shaking。
  static IconData _mapIconCodePoint(int codePoint) {
    for (final icon in categoryIcons) {
      if (icon.codePoint == codePoint) return icon;
    }
    return Icons.folder;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileCategory && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}
