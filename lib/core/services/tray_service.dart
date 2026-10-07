import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// 桌面端系统托盘服务（全局单例）
///
/// 负责管理系统托盘图标的创建、菜单交互和窗口显示/隐藏。
/// 点击关闭按钮时最小化到托盘而非退出应用，
/// 只有通过托盘右键菜单"退出"才能关闭应用。
class TrayService with TrayListener {
  static final TrayService instance = TrayService._();

  TrayService._();

  /// 托盘图标路径
  ///
  /// Windows 的 LoadImage(IMAGE_ICON, LR_LOADFROMFILE) 仅支持 .ico/.bmp 格式，
  /// 不支持 .png，因此 Windows 使用 .ico 文件。
  /// macOS / Linux 通过 rootBundle 加载，支持 .png。
  /// 该文件同时作为桌面端应用内侧边栏的 Logo 使用。
  static final String _kTrayIconPath =
      Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png';

  bool _initialized = false;

  /// 显示窗口回调（由外部设置，使用 window_manager 实现）
  Future<void> Function()? onShowWindow;

  /// 隐藏窗口回调（由外部设置）。
  ///
  /// 退出前若窗口未隐藏到托盘，先隐藏窗口，否则 Windows 在进程退出时
  /// 会等待窗口/托盘资源释放，导致退出卡顿数秒。
  Future<void> Function()? onHideWindow;

  /// 退出应用回调（由外部设置）
  Future<void> Function()? onExitApp;

  /// 初始化系统托盘
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }

    try {
      trayManager.addListener(this);
      debugPrint('[TrayService] 已注册监听器');

      // trayManager.setIcon 内部会自动将路径拼接为：
      // {exe}/data/flutter_assets/{iconPath}
      // Windows 需要 .ico 文件（LoadImage 不支持 PNG）
      await trayManager.setIcon(_kTrayIconPath);
      debugPrint('[TrayService] 图标已设置: $_kTrayIconPath');

      // 设置工具提示
      await trayManager.setToolTip('享联 - 跨设备无缝互联');

      // 设置右键菜单
      final menu = Menu(
        items: [
          MenuItem(key: 'show', label: '显示窗口'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      );
      await trayManager.setContextMenu(menu);
      debugPrint('[TrayService] 菜单已设置');

      _initialized = true;
      debugPrint('[TrayService] 系统托盘初始化完成');
    } catch (e) {
      debugPrint('[TrayService] 初始化失败: $e');
    }
  }

  /// 处理托盘菜单点击
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    debugPrint('[TrayService] 菜单点击: ${menuItem.key}');
    switch (menuItem.key) {
      case 'show':
        onShowWindow?.call();
        break;
      case 'exit':
        _handleExit();
        break;
    }
  }

  /// 左键按下时显示窗口
  ///
  /// Windows 端 WM_LBUTTONUP 事件映射到 onTrayIconMouseDown（而非 onTrayIconMouseUp），
  /// 所以必须 override 此方法才能响应左键点击。
  @override
  void onTrayIconMouseDown() {
    debugPrint('[TrayService] 图标左键按下');
    onShowWindow?.call();
  }

  /// 鼠标在托盘图标上松开时显示窗口（macOS / Linux 回调）
  @override
  void onTrayIconMouseUp() {
    debugPrint('[TrayService] 图标左键松开');
    onShowWindow?.call();
  }

  /// 右键按下时弹出上下文菜单
  ///
  /// Windows 端不会自动弹出右键菜单，需要在 onTrayIconRightMouseDown 中
  /// 显式调用 popUpContextMenu()。
  @override
  void onTrayIconRightMouseDown() {
    debugPrint('[TrayService] 图标右键按下，弹出菜单');
    trayManager.popUpContextMenu();
  }

  /// 处理退出
  ///
  /// 顺序：先隐藏窗口（若未隐藏到托盘）→ 销毁托盘图标 → 销毁窗口并退出进程。
  /// 窗口可见时直接退出，Windows 会等待窗口/托盘资源释放导致卡顿数秒；
  /// 先隐藏窗口可避免该等待。用微任务延迟到菜单回调返回后再执行，
  /// 避免在原生托盘菜单回调上下文里操作导致挂起。
  void _handleExit() async {
    await Future<void>.delayed(Duration.zero);
    await onHideWindow?.call();
    await dispose();
    await onExitApp?.call();
  }

  /// 销毁托盘
  Future<void> dispose() async {
    if (!_initialized) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
    debugPrint('[TrayService] 托盘已销毁');
  }
}