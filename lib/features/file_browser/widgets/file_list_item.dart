import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/file_item.dart';

class FileListItem extends StatelessWidget {
  final FileItem file;

  const FileListItem({super.key, required this.file});

  IconData _getIcon() {
    if (file.isImage) return Icons.image;
    if (file.isVideo) return Icons.video_file;
    if (file.isText) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _getIconColor() {
    if (file.isImage) return Colors.redAccent;
    if (file.isVideo) return Colors.teal;
    if (file.isText) return Colors.amber;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () {
          // TODO: 打开文件预览
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getIcon(), size: 40, color: _getIconColor()),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
