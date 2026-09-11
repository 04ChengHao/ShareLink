import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// 单个操作项
class FileAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const FileAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });
}

/// 在文件卡片上方弹出操作列表（带全屏蒙版）
///
/// [anchorContext] 用于定位卡片在屏幕上的位置，操作列表渲染在卡片上方。
/// 点击蒙版或空白处关闭。返回在关闭时完成。
Future<void> showFileActions(
  BuildContext context, {
  required BuildContext anchorContext,
  required List<FileAction> actions,
}) {
  final overlayState = Overlay.of(context);
  final completer = Completer<void>();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _FileActionsOverlay(
      anchorContext: anchorContext,
      actions: actions,
      onDismiss: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );

  overlayState.insert(entry);
  return completer.future;
}

class _FileActionsOverlay extends StatefulWidget {
  final BuildContext anchorContext;
  final List<FileAction> actions;
  final VoidCallback onDismiss;

  const _FileActionsOverlay({
    required this.anchorContext,
    required this.actions,
    required this.onDismiss,
  });

  @override
  State<_FileActionsOverlay> createState() => _FileActionsOverlayState();
}

class _FileActionsOverlayState extends State<_FileActionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 0.08, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close() {
    _ctrl.reverse().whenComplete(widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final overlaySize = MediaQuery.of(context).size;

    // 定位卡片
    final box = widget.anchorContext.findRenderObject() as RenderBox?;
    const menuWidth = 108.0;
    var menuLeft = overlaySize.width - menuWidth - 12.0;
    var menuBottom = overlaySize.height - 100.0;

    if (box != null) {
      final position = box.localToGlobal(Offset.zero);
      menuLeft = (position.dx + box.size.width - menuWidth)
          .clamp(8.0, (overlaySize.width - menuWidth - 8.0));
      // 菜单底边位于卡片顶边上方 8px
      menuBottom = overlaySize.height - position.dy + 8.0;
    }

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // 全屏蒙版
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          // 顶部渐变遮罩（增强层级感）
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.28)),
            ),
          ),
          // 操作列表
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, _slide.value),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
              child: Container(
                width: menuWidth,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: colors.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: colors.inputBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.actions.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: colors.inputBorder.withValues(alpha: 0.6),
                          ),
                        ),
                      _ActionItem(action: widget.actions[i], onClose: _close),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatefulWidget {
  final FileAction action;
  final VoidCallback onClose;

  const _ActionItem({required this.action, required this.onClose});

  @override
  State<_ActionItem> createState() => _ActionItemState();
}

class _ActionItemState extends State<_ActionItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onClose();
            widget.action.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _hovering
                ? colors.primaryWithAlpha(0.08)
                : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  widget.action.icon,
                  size: 20,
                  color: widget.action.color ?? colors.iconActive,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.action.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.action.color ?? colors.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}