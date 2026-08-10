import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/file_item.dart';

/// 文件列表项（上方封面，下方文件名）
class FileListItem extends StatelessWidget {
  final FileItem file;
  final bool showFileName;

  const FileListItem({super.key, required this.file, this.showFileName = true});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 封面区域
        Expanded(child: _buildCover(colors)),
        // 文件名区域（固定高度占位）
        SizedBox(
          height: 28,
          child: showFileName
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  /// 构建封面
  Widget _buildCover(AppColorScheme colors) {
    final typeColor = file.typeColor;

    if (file.hasCover) {
      // 图片/视频：渐变背景 + 图标（静态测试，后续替换为真实缩略图）
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    typeColor.withValues(alpha: 0.3),
                    typeColor.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            Center(
              child: Icon(
                file.isImage ? Icons.image : Icons.video_file,
                size: 36,
                color: typeColor,
              ),
            ),
            if (file.isVideo)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // 其他文件：文件类型图标或后缀名当封面
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBg,
          border: Border.all(color: colors.inputBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              file.typeIcon,
              size: 32,
              color: typeColor,
            ),
            const SizedBox(height: 4),
            if (file.extension.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  file.extension.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
