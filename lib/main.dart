import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'shared/widgets/window_manager_stub.dart';

import 'app.dart';
import 'core/services/storage_service.dart';
import 'core/services/tray_service.dart';
import 'features/file_browser/services/remote_file_service.dart';

@pragma('vm:entry-point')
void backgroundServiceEntryPoint(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

// TODO: 修改文件管理：1、图片预览页面中的按钮胶囊都太小了，都需要放大一点。2、图片旋转后，触摸点击移动图片上下滑动图片，图片却是左右移动。3、视频预览页面中的音量：图标，数值，进度条间隔需要缩小一些，进度条加粗一点。静音点击应该恢复成原来的音量，而不是100。4、桌面端视频的音量控制不需要控制系统音量，和系统音量单独区分（手机端不变）。5、视频播放页面增加快捷视频倍速功能：桌面端增加键盘映射：（左方向键/a）进度条后退，（右方向键/d）进度条快进。长按快进键会进入2倍速播放。（上下方向键/鼠标滚轮）调整音量大小，10以上一次步长10，10以下步长2。手机端增加触摸倍速：在屏幕右侧区域长按会进入2倍速播放。进入倍速播放后都需要在屏幕中央上方显示”2倍速播放中“。

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地存储
  final prefs = await SharedPreferences.getInstance();

  // 初始化媒体播放器（media_kit，全平台统一支持）
  MediaKit.ensureInitialized();

  // 清空远程文件临时缓存目录（应用启动时）
  RemoteFileService.instance.startCleanupTimer();
  await RemoteFileService.instance.clearAllTempFiles();

  // 移动端：初始状态栏样式
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
  }

  // 桌面端初始化
  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 760),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(800, 560),
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 初始化系统托盘（全局单例）
    final trayService = TrayService.instance;
    trayService.onShowWindow = () async {
      await windowManager.show();
      await windowManager.focus();
    };
    trayService.onExitApp = () async {
      await windowManager.destroy();
      exit(0);
    };
    await trayService.init();
  }

  // 手机端：初始化后台服务
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (isMobile) {
    try {
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: backgroundServiceEntryPoint,
          autoStart: true,
          isForegroundMode: true,
          initialNotificationTitle: '享联',
          initialNotificationContent: '设备发现服务正在运行',
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: backgroundServiceEntryPoint,
          onBackground: null,
        ),
      );
      debugPrint('[BackgroundService] 后台服务已配置');
    } catch (e) {
      debugPrint('[BackgroundService] 配置失败: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ShareLinkApp(),
    ),
  );
}
