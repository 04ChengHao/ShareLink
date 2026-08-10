import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../providers/settings_provider.dart';

/// 桌面端共享内容右侧抽屉弹窗
///
/// 仅显示文件夹管理（添加 / 删除共享文件夹）。
/// 使用 AnimationController 实现从右侧缓缓滑入的动画。
void showSharedContentDesktopDrawer(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      // 从右侧滑入
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));
      return SlideTransition(position: offset, child: child);
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _DesktopSharedDrawer();
    },
  );
}

class _DesktopSharedDrawer extends ConsumerWidget {
  const _DesktopSharedDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
    final settings = ref.watch(sharedContentProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 400,
          height: screenHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(-4, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 16, 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_shared_outlined,
                      size: 24,
                      color: colors.iconPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppStrings.sharedContent,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      color: colors.iconSecondary,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.divider),
              // 副标题
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  AppStrings.sharedFolderSub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              // 文件夹列表
              Expanded(
                child: settings.folders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 48,
                              color: colors.iconSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppStrings.noFolders,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: settings.folders.length,
                        itemBuilder: (context, index) {
                          final path = settings.folders[index];
                          final name = path.split(RegExp(r'[/\\]')).last;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colors.inputBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder,
                                  size: 20,
                                  color: colors.iconSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: colors.textPrimary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        path,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                              fontSize: 11,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: colors.textSecondary,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(
                                          sharedContentProvider.notifier,
                                        )
                                        .removeFolder(path);
                                  },
                                  tooltip: AppStrings.removeFolder,
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.all(5),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              // 底部添加按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _pickFolder(ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(AppStrings.addFolder),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFolder(WidgetRef ref) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: AppStrings.selectFolder,
    );
    if (result != null) {
      ref.read(sharedContentProvider.notifier).addFolder(result);
    }
  }
}
