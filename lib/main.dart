import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'shared/widgets/window_manager_stub.dart';

import 'app.dart';
import 'core/services/storage_service.dart';
import 'core/services/tray_service.dart';

@pragma('vm:entry-point')
void backgroundServiceEntryPoint(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地存储
  final prefs = await SharedPreferences.getInstance();

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
