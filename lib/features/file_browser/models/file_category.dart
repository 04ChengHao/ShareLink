import 'package:flutter/material.dart';

import 'file_item.dart';

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

  /// 将 iconCodePoint 映射回 IconData
  static IconData _mapIconCodePoint(int codePoint) {
    // ignore: non_const_argument_for_const_parameter
    return IconData(codePoint, fontFamily: 'MaterialIcons');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileCategory && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}
