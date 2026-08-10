import 'dart:ui';

/// Web 平台 window_manager 占位实现
class WindowOptions {
  final Size? size;
  final bool? center;
  final Color? backgroundColor;
  final bool? skipTaskbar;
  final TitleBarStyle? titleBarStyle;
  final Size? minimumSize;
  final Size? maximumSize;

  const WindowOptions({
    this.size,
    this.center,
    this.backgroundColor,
    this.skipTaskbar,
    this.titleBarStyle,
    this.minimumSize,
    this.maximumSize,
  });
}

enum TitleBarStyle { hidden, normal }

class _WindowManagerStub {
  Future<void> ensureInitialized() async {}

  Future<void> waitUntilReadyToShow(
    WindowOptions options,
    VoidCallback callback,
  ) async {
    callback();
  }

  Future<void> show() async {}
  Future<void> focus() async {}
  Future<void> hide() async {}
  Future<void> minimize() async {}
  Future<void> maximize() async {}
  Future<void> unmaximize() async {}
  Future<bool> isMaximized() async => false;
  Future<void> setFullScreen(bool isFullScreen) async {}
  Future<bool> isFullScreen() async => false;
  Future<void> close() async {}
  Future<void> startDragging() async {}
}

final windowManager = _WindowManagerStub();
