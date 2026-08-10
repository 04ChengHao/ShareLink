import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'window_manager_stub.dart';

import 'window_controls.dart';

/// 桌面端自定义标题栏：左侧可拖拽区域 + 右侧窗口控制按钮
class WindowTitleBar extends StatelessWidget {
  final Widget? title;

  const WindowTitleBar({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 40,
        color: Colors.transparent,
        child: Row(
          children: [
            const SizedBox(width: 16),
            if (title != null) ...[title!, const SizedBox(width: 16)],
            const Expanded(child: SizedBox()),
            const WindowControls(),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}
