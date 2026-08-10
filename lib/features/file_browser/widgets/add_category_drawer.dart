import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import 'add_category_form.dart';

/// 桌面端添加分类右侧抽屉弹窗
void showAddCategoryDesktopDrawer(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
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
      return _AddCategoryDesktopDrawer(
        messenger: messenger,
      );
    },
  );
}

class _AddCategoryDesktopDrawer extends StatelessWidget {
  final ScaffoldMessengerState messenger;

  const _AddCategoryDesktopDrawer({required this.messenger});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColorScheme.of(context);
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
                      Icons.add_circle_outline,
                      size: 24,
                      color: colors.iconPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppStrings.addCategory,
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
              // 表单内容
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AddCategoryForm(
                    onSaved: (name) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('分类「$name」添加成功'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
