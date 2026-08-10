import 'package:flutter_background_service/flutter_background_service.dart';

import '../utils/logger.dart';

/// 后台服务管理
class BackgroundService {
  BackgroundService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'share_link_service',
        initialNotificationTitle: '享联 ShareLink',
        initialNotificationContent: '正在监听剪贴板变化...',
        foregroundServiceNotificationId: 1001,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<bool> start() async {
    return await _service.startService();
  }

  static Future<void> stop() async {
    _service.invoke('stop');
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    appLogger.i('后台服务已启动');

    service.on('stop').listen((event) {
      service.stopSelf();
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }
}
