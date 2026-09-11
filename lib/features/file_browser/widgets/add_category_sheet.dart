import 'package:flutter/material.dart';
import 'package:unified_popups/unified_popups.dart'
    hide ToastType;

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_toast.dart';
import 'add_category_form.dart';

/// 手机端添加分类底部弹窗，返回保存的分类名（null 表示取消）
Future<String?> showAddCategoryMobileSheet(BuildContext context) async {
  final handle = Pop.sheet<String>(
    SheetConfig<String>(
      direction: SheetDirection.bottom,
      header: const SheetHeaderConfig(
        title: AppStrings.addCategory,
        showCloseButton: true,
      ),
      size: const SheetSizeConfig(
        height: SheetDimension.fraction(0.67),
        maxHeight: SheetDimension.fraction(1.0),
      ),
      drag: const SheetDragConfig(
        showHandle: true,
        mode: SheetDragDismissMode.fullBody,
      ),
      builder: (context, handle) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AddCategoryForm(
            onSaved: (name) => handle.complete(name),
          ),
        );
      },
    ),
  );

  // 等待 sheet 完全关闭（包括动画），再显示 toast，避免黑屏
  final name = await handle.result;
  if (name != null && context.mounted) {
    showAppToast(context, '分类「$name」添加成功', type: ToastType.success);
  }
  return name;
}
