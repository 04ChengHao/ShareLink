import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/platform_utils.dart';

/// 桌面端与手机端通用的视频播放器组件
///
/// 基于 media_kit（libmpv），全平台支持网络流播放和 Range 请求。
///
/// **手机端交互**：
/// - 单击：显示/隐藏控制栏
/// - 双击：播放/暂停
/// - 左右滑动：拖动进度
/// - 左半屏上下滑动：调节屏幕亮度（仅作用于当前页面，退出恢复）
/// - 右半屏上下滑动：调节播放器音量（仅作用于当前播放器）
/// - 控制栏自动隐藏（3 秒无操作）
/// - 全屏顶部包含返回按钮、标题、屏幕旋转按钮
/// - 全屏侧滑返回拦截为"退出全屏"
///
/// **桌面端交互**：
/// - 单击：显示/隐藏控制栏
/// - 双击：播放/暂停
/// - 鼠标在内容区域移动：显示控制栏
/// - 鼠标停留 1 秒后：隐藏控制栏
/// - 滚轮：调节音量（<10 步长 2，>=10 步长 10）
/// - 键盘：左/上 ... 右/下 后退/快进 10 秒（长按 500ms 进入 2 倍速）
/// - 键盘：上/下 增大/减小音量（<10 步长 2，>=10 步长 10）
/// - 控制栏自动隐藏（3 秒无操作）
class VideoViewer extends StatefulWidget {
  final String mediaUri;
  final String title;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onBack;

  /// 缓存里已有的时长（毫秒），用于加载前直接显示总时长
  final int? knownDurationMs;

  /// 当播放器确定媒体真实时长时回调（用于把时长回写入缓存）
  final void Function(Duration duration)? onDurationKnown;

  const VideoViewer({
    super.key,
    required this.mediaUri,
    required this.title,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onBack,
    this.onDurationKnown,
    this.knownDurationMs,
  });

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  late final Player _player;
  late final VideoController _controller;

  // 播放状态
  bool _initialized = false;
  bool _failed = false;
  bool _showControls = true;
  double _playbackSpeed = 1.0;

  // 缓冲状态：初始加载时即为 true，直到有足够缓冲
  bool _buffering = true;
  Duration _buffer = Duration.zero;
  // 已知时长：优先取缓存（加载前直接显示），播放器加载后如有变化再更新
  Duration _knownDuration = Duration.zero;
  Duration get _resolvedDuration =>
      _player.state.duration.inMilliseconds > 0
          ? _player.state.duration
          : _knownDuration;

  // 手势状态（进度条拖动）
  // 使用绝对位置计算，避免 delta 累积导致的跳动问题
  double _dragStartProgress = 0.0;
  double _seekPreviewProgress = 0.0;
  bool _isDraggingProgress = false;
  bool _isAdjustingVolume = false;
  // 记录手势起始位置，用于判断滑动方向
  Offset _dragStartPosition = Offset.zero;
  // 手势类型：0=未确定，1=水平（进度），2=垂直（亮度/音量）
  int _dragAxis = 0;
  // 垂直手势提示（亮度/音量）
  String _verticalHint = '';
  double _verticalHintValue = 0.0;
  // 垂直手势起始值
  double _dragStartBrightness = 0.0;
  double _dragStartVolume = 0.0;

  // 自动隐藏计时器
  Timer? _hideTimer;
  // 桌面端鼠标停留计时器
  Timer? _mouseIdleTimer;

  // 屏幕亮度控制器（手机端，仅作用于当前页面）
  final ScreenBrightness _screenBrightness = ScreenBrightness.instance;
  double? _originalBrightness;
  double _currentBrightness = 0.5;

  // 音量
  double _currentVolume = 100.0;
  double? _originalVolume;
  // 静音前的音量，用于取消静音时恢复
  double? _volumeBeforeMute;

  // 全屏旋转模式：true=横屏，false=竖屏
  bool _landscapeMode = true;

  // 倍速播放状态（长按触发）
  bool _isLongPressSpeed = false;
  // 桌面端长按方向键进入倍速模式的延时计时器
  Timer? _speedModeTimer;
  // 桌面端键盘事件焦点
  final FocusNode _focusNode = FocusNode();

  /// 手机端使用系统音量，桌面端使用播放器音量
  bool get _useSystemVolume => PlatformUtils.isMobile;

  // 流订阅
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _knownDuration = widget.knownDurationMs != null
        ? Duration(milliseconds: widget.knownDurationMs!)
        : Duration.zero;
    _initPlayer();
    _startHideTimer();
    // 保存系统亮度，用于退出时恢复
    if (PlatformUtils.isMobile) {
      _screenBrightness.application.then((b) {
        _originalBrightness = b;
        _currentBrightness = b;
      }).catchError((_) {});
    }

    // 保存系统音量，用于退出时恢复
    _initSystemVolume();
  }

  Future<void> _initSystemVolume() async {
    if (!_useSystemVolume) {
      // 桌面端：使用播放器音量，初始化为播放器当前音量
      _currentVolume = _player.state.volume.clamp(0.0, 100.0);
      if (mounted) setState(() {});
      return;
    }
    try {
      // 不显示系统音量 UI
      VolumeController.instance.showSystemUI = false;
      // 监听系统音量变化（如用户通过物理按键调节）
      // addListener 返回 0.0-1.0 的值
      VolumeController.instance.addListener((volume) {
        if (mounted) {
          setState(() => _currentVolume = volume * 100);
        }
      });
      final vol = await VolumeController.instance.getVolume();
      _originalVolume = vol * 100;
      _currentVolume = vol * 100;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[VideoViewer] 获取系统音量失败: $e');
    }
  }

  Future<void> _initPlayer() async {
    // 立即显示 UI，不等待打开完成（大文件流式加载，避免长时间黑屏）
    _initialized = true;

    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (mounted) setState(() {});
    }));
    _subscriptions.add(_player.stream.position.listen((_) {
      if (mounted && !_isDraggingProgress) setState(() {});
    }));
    _subscriptions.add(_player.stream.duration.listen((d) {
      if (mounted) setState(() {});
      if (d > Duration.zero) widget.onDurationKnown?.call(d);
      // 播放器加载出真实时长：与缓存/已知不同才更新并写回，相同则不动
      final real = _player.state.duration;
      if (real.inMilliseconds > 0 && real != _knownDuration) {
        _knownDuration = real;
        widget.onDurationKnown?.call(d);
      }
    }));
    _subscriptions.add(_player.stream.completed.listen((_) {
      if (mounted) setState(() {});
    }));
    _subscriptions.add(_player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    }));
    _subscriptions.add(_player.stream.buffer.listen((b) {
      if (mounted) setState(() => _buffer = b);
    }));
    _subscriptions.add(_player.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('[VideoViewer] 播放错误: $error');
        setState(() => _failed = true);
      }
    }));

    try {
      await _player.open(Media(widget.mediaUri));
      await _player.setRate(_playbackSpeed);
      _player.play();
    } catch (e) {
      debugPrint('[VideoViewer] 初始化失败: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _mouseIdleTimer?.cancel();
    _speedModeTimer?.cancel();
    _focusNode.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    // 恢复屏幕亮度到系统值（仅手机端，且仅恢复我们修改过的）
    if (PlatformUtils.isMobile && _originalBrightness != null) {
      _screenBrightness
          .resetApplicationScreenBrightness()
          .catchError((_) {});
    }
    // 手机端：移除音量监听并恢复原始系统音量（桌面端不影响系统音量）
    if (_useSystemVolume) {
      VolumeController.instance.removeListener();
      if (_originalVolume != null) {
        VolumeController.instance
            .setVolume(_originalVolume! / 100.0)
            .catchError((_) {});
      }
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 控制栏自动隐藏
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _showControls &&
          !_isDraggingProgress &&
          !_isAdjustingVolume) {
        setState(() => _showControls = false);
      }
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _showControlsOverlay() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  /// 单击切换控制台显隐
  void _toggleControls() {
    _focusNode.requestFocus();
    if (_showControls) {
      setState(() => _showControls = false);
      _cancelHideTimer();
    } else {
      _showControlsOverlay();
    }
  }

  // ---------------------------------------------------------------------------
  // 桌面端鼠标移动处理
  // ---------------------------------------------------------------------------

  void _onMouseHover() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    // 重置鼠标停留计时器
    _mouseIdleTimer?.cancel();
    _mouseIdleTimer = Timer(const Duration(seconds: 1), () {
      if (mounted &&
          _showControls &&
          !_isDraggingProgress &&
          !_isAdjustingVolume) {
        setState(() => _showControls = false);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 播放控制
  // ---------------------------------------------------------------------------

  void _togglePlay() {
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _showControlsOverlay();
  }

  void _seekRelative(int seconds) {
    final pos = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    final clamped = pos < Duration.zero
        ? Duration.zero
        : (pos > duration ? duration : pos);
    _player.seek(clamped);
    _showControlsOverlay();
  }

  void _cycleSpeed() {
    const speeds = [0.5, 1.0, 1.5, 2.0];
    final idx = speeds.indexOf(_playbackSpeed);
    _playbackSpeed = speeds[(idx + 1) % speeds.length];
    _player.setRate(_playbackSpeed);
    setState(() {});
    _showControlsOverlay();
  }

  Future<void> _toggleRotation() async {
    setState(() => _landscapeMode = !_landscapeMode);
    if (_landscapeMode) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    _showControlsOverlay();
  }

  Future<void> _setVolume(double vol) async {
    _currentVolume = vol.clamp(0.0, 100.0);
    if (_currentVolume > 0) {
      _volumeBeforeMute = _currentVolume;
    }
    if (_useSystemVolume) {
      // 手机端：调节系统音量（退出时恢复原值）
      try {
        await VolumeController.instance.setVolume(_currentVolume / 100.0);
      } catch (e) {
        debugPrint('[VideoViewer] 设置系统音量失败: $e');
      }
    } else {
      // 桌面端：仅调节播放器音量，不控制系统音量（media_kit 的 setVolume 范围是 0-100）
      await _player.setVolume(_currentVolume);
    }
    setState(() {});
  }

  /// 切换静音：记住静音前的音量，取消静音时恢复
  void _toggleMute() {
    if (_currentVolume > 0) {
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute ?? 50.0);
    }
    _startHideTimer();
  }

  Future<void> _setBrightness(double b) async {
    _currentBrightness = b.clamp(0.0, 1.0);
    try {
      await _screenBrightness.setApplicationScreenBrightness(_currentBrightness);
    } catch (_) {}
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 倍速播放（长按触发）
  // ---------------------------------------------------------------------------

  void _enterSpeedMode() {
    if (!_isLongPressSpeed) {
      _isLongPressSpeed = true;
      _player.setRate(2.0);
      setState(() {});
    }
  }

  void _exitSpeedMode() {
    if (_isLongPressSpeed) {
      _isLongPressSpeed = false;
      _player.setRate(_playbackSpeed);
      setState(() {});
    }
  }

  /// 桌面端键盘事件：方向键/A、D 控制进度与倍速，上下键控制音量
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // 音量控制：上下方向键
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) {
        final step = _currentVolume < 10 ? 2 : 10;
        if (key == LogicalKeyboardKey.arrowUp) {
          _setVolume(_currentVolume + step);
        } else {
          _setVolume(_currentVolume - step);
        }
        _showControlsOverlay();
      }
      return KeyEventResult.handled;
    }
    // 空格控制播放/暂停
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent && event is! KeyRepeatEvent) {
        _togglePlay();
      }
      return KeyEventResult.handled;
    }

    // 进度控制：左右方向键/A、D
    final isForward = key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD;
    final isBackward = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA;
    if (!isForward && !isBackward) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (event is KeyRepeatEvent) return KeyEventResult.ignored;
      if (isBackward) {
        _seekRelative(-10);
      } else if (isForward) {
        _speedModeTimer?.cancel();
        _speedModeTimer = Timer(const Duration(milliseconds: 500), () {
          _enterSpeedMode();
        });
      }
    } else if (event is KeyUpEvent) {
      if (isForward) {
        _speedModeTimer?.cancel();
        if (_isLongPressSpeed) {
          _exitSpeedMode();
        } else {
          _seekRelative(10);
        }
      }
    }
    return KeyEventResult.handled;
  }

  /// 桌面端鼠标滚轮调节音量
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final step = _currentVolume < 10 ? 2 : 10;
      final delta = event.scrollDelta.dy < 0 ? step : -step;
      _setVolume(_currentVolume + delta);
      _showControlsOverlay();
    }
  }

  /// 手机端：长按右半屏进入倍速播放
  void _onLongPressStart(LongPressStartDetails details) {
    if (details.localPosition.dx >= MediaQuery.of(context).size.width / 2) {
      _enterSpeedMode();
    }
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _exitSpeedMode();
  }

  // ---------------------------------------------------------------------------
  // 手势识别（手机端）
  // 使用绝对位置计算，避免 delta 累积导致的跳动问题
  // ---------------------------------------------------------------------------

  /// 手势起始：记录起始位置和当前进度/亮度/音量值
  void _onPanStart(DragStartDetails details) {
    _dragStartPosition = details.localPosition;
    _dragAxis = 0; // 未确定方向

    final isLeftSide =
        details.localPosition.dx < MediaQuery.of(context).size.width / 2;

    _dragStartProgress = _currentProgress;
    _dragStartBrightness = _currentBrightness;
    _dragStartVolume = _currentVolume;
    _verticalHint = isLeftSide ? '亮度' : '音量';
    _cancelHideTimer();
  }

  /// 手势更新：根据起始位置和当前位置的绝对差值计算
  void _onPanUpdate(DragUpdateDetails details) {
    final dx = details.localPosition.dx - _dragStartPosition.dx;
    final dy = details.localPosition.dy - _dragStartPosition.dy;

    // 首次更新时确定手势方向（水平或垂直）
    if (_dragAxis == 0) {
      if (dx.abs() > dy.abs() && dx.abs() > 10) {
        _dragAxis = 1; // 水平：进度
        _isDraggingProgress = true;
      } else if (dy.abs() > dx.abs() && dy.abs() > 10) {
        _dragAxis = 2; // 垂直：亮度/音量
      } else {
        return; // 未达到阈值，不处理
      }
    }

    if (_dragAxis == 1) {
      // 水平拖动：调节进度（基于绝对位置，不累积 delta）
      final width = MediaQuery.of(context).size.width;
      final progressDelta = (dx / width) * 2; // 放大系数
      setState(() {
        _seekPreviewProgress =
            (_dragStartProgress + progressDelta).clamp(0.0, 1.0);
      });
    } else if (_dragAxis == 2) {
      // 垂直拖动：调节亮度/音量（基于绝对 Y 位置差）
      final height = MediaQuery.of(context).size.height;
      // 向上滑 = 增大，向下滑 = 减小
      final delta = -dy / height;

      if (_verticalHint == '亮度') {
        _setBrightness(_dragStartBrightness + delta * 1.5);
        _verticalHintValue = _currentBrightness;
      } else {
        _setVolume(_dragStartVolume + delta * 100);
        _verticalHintValue = _currentVolume / 100.0;
      }
    }
  }

  /// 手势结束：根据手势类型执行最终操作
  void _onPanEnd(DragEndDetails _) {
    if (_dragAxis == 1 && _isDraggingProgress) {
      // 水平拖动结束：seek 到目标位置
      final duration = _player.state.duration;
      _player.seek(
        Duration(
          milliseconds:
              (_seekPreviewProgress * duration.inMilliseconds).toInt(),
        ),
      );
      _isDraggingProgress = false;
      _seekPreviewProgress = 0.0;
    }

    _dragAxis = 0;
    setState(() => _verticalHint = '');
    _startHideTimer();
  }

  double get _currentProgress {
    final duration = _player.state.duration;
    final position = _player.state.position;
    if (duration.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 加载提示文案：初始加载（无时长）显示"加载中"，缓冲时显示缓冲百分比
  String _getLoadingText() {
    final duration = _player.state.duration;
    if (duration.inMilliseconds <= 0) return '加载中...';
    final percent = (_buffer.inMilliseconds / duration.inMilliseconds * 100)
        .clamp(0, 100)
        .toInt();
    return '缓冲中 $percent%';
  }

  // ---------------------------------------------------------------------------
  // 构建 UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);

    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.textHint),
            const SizedBox(height: 12),
            Text(
              AppStrings.fileLoadFailed,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接或文件是否存在',
              style: TextStyle(color: colors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (!_initialized) {
      return Center(
        child: CircularProgressIndicator(color: colors.iconActive),
      );
    }

    // 全屏模式下拦截侧滑返回为"退出全屏"
    if (widget.isFullscreen && PlatformUtils.isMobile) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.onBack != null) {
            widget.onBack!();
          }
        },
        child: _buildBody(colors),
      );
    }

    return _buildBody(colors);
  }

  Widget _buildBody(AppColorScheme colors) {
    final isDesktop = PlatformUtils.isDesktop;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: isDesktop ? _onKeyEvent : null,
        child: Listener(
          onPointerSignal: isDesktop ? _onPointerSignal : null,
          onPointerDown: (_) => _focusNode.requestFocus(),
          child: MouseRegion(
            // 桌面端：鼠标移动显示控制栏
            onHover: isDesktop ? (_) => _onMouseHover() : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: _togglePlay,
              // 手机端使用 Pan 手势（统一处理水平和垂直滑动）
              onPanStart: isDesktop ? null : _onPanStart,
              onPanUpdate: isDesktop ? null : _onPanUpdate,
              onPanEnd: isDesktop ? null : _onPanEnd,
              // 手机端：长按右半屏 2 倍速播放
              onLongPressStart: isDesktop ? null : _onLongPressStart,
              onLongPressEnd: isDesktop ? null : _onLongPressEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 视频画面
                  Video(
                    controller: _controller,
                    fill: Colors.black,
                    controls: NoVideoControls,
                  ),

                  // 加载 / 缓冲状态（在正中央显示 loading 和数值进度）
                  if (_buffering)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _getLoadingText(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 进度拖动预览
                  if (_isDraggingProgress)
                    Positioned(
                      top: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_formatDuration(Duration(milliseconds: (_seekPreviewProgress * _player.state.duration.inMilliseconds).toInt()))} / ${_formatDuration(_player.state.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 倍速播放指示器（长按或长按方向键触发）
                  if (_isLongPressSpeed)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                '2倍速播放中',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 垂直手势提示（亮度/音量）
                  if (_verticalHint.isNotEmpty && _dragAxis == 2)
                    Positioned(
                      top: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _verticalHint == '亮度'
                                    ? Icons.brightness_6
                                    : Icons.volume_up,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$_verticalHint: ${(_verticalHintValue * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 控制层
                  if (_showControls) ..._buildControls(colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  List<Widget> _buildControls(AppColorScheme colors) {
    final duration = _resolvedDuration;
    final position = _player.state.position;
    final progress = _isDraggingProgress
        ? _seekPreviewProgress
        : (duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0);

    return [
      // 顶部渐变遮罩 + 操作栏
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            8,
            widget.isFullscreen ? MediaQuery.of(context).padding.top + 8 : 8,
            8,
            8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              // 返回按钮（仅全屏显示）
              if (widget.isFullscreen && widget.onBack != null)
                _IconButtonWithTooltip(
                  icon: Icons.arrow_back,
                  tooltip: '退出全屏',
                  onPressed: widget.onBack,
                ),
              // 标题
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 屏幕旋转按钮（仅手机端全屏）
              if (widget.isFullscreen && PlatformUtils.isMobile)
                _IconButtonWithTooltip(
                  icon: _landscapeMode
                      ? Icons.stay_current_portrait
                      : Icons.stay_current_landscape,
                  tooltip: _landscapeMode ? '切换为竖屏' : '切换为横屏',
                  onPressed: _toggleRotation,
                ),
              // 倍速
              _TooltipButton(
                tooltip: '播放速度',
                child: GestureDetector(
                  onTap: _cycleSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              // 全屏切换
              if (widget.onToggleFullscreen != null)
                _IconButtonWithTooltip(
                  icon: widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
                  onPressed: widget.onToggleFullscreen,
                ),
            ],
          ),
        ),
      ),

      // 中央播放/暂停大按钮（缓冲加载时不显示）
      if (!_buffering)
        Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 64,
              icon: Icon(
                _player.state.playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _togglePlay,
            ),
          ),
        ),

      // 底部控制栏
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            widget.isFullscreen
                ? MediaQuery.of(context).padding.bottom + 12
                : 12,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChangeStart: (_) {
                          _isDraggingProgress = true;
                          _seekPreviewProgress = progress;
                          _cancelHideTimer();
                        },
                        onChanged: (v) {
                          setState(() => _seekPreviewProgress = v);
                        },
                        onChangeEnd: (v) {
                          _player.seek(
                            Duration(
                              milliseconds:
                                  (v * duration.inMilliseconds).toInt(),
                            ),
                          );
                          _isDraggingProgress = false;
                          _startHideTimer();
                        },
                        activeColor: colors.iconActive,
                        inactiveColor: Colors.white30,
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              // 按钮栏（含常驻音量条）
              Row(
                children: [
                  // 快退 10s
                  _IconButtonWithTooltip(
                    icon: Icons.replay_10,
                    tooltip: '后退 10 秒',
                    iconSize: 28,
                    onPressed: () => _seekRelative(-10),
                  ),
                  // 播放/暂停
                  _IconButtonWithTooltip(
                    icon: _player.state.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    tooltip: _player.state.playing ? '暂停' : '播放',
                    iconSize: 44,
                    onPressed: _togglePlay,
                  ),
                  // 快进 10s
                  _IconButtonWithTooltip(
                    icon: Icons.forward_10,
                    tooltip: '前进 10 秒',
                    iconSize: 28,
                    onPressed: () => _seekRelative(10),
                  ),
                  const Spacer(),
                  // 音量按钮 + 数字 + 常驻音量条
                  Tooltip(
                    message: _currentVolume <= 0 ? '取消静音' : '静音',
                    waitDuration: const Duration(milliseconds: 300),
                    showDuration: const Duration(seconds: 2),
                    preferBelow: false,
                    verticalOffset: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    child: InkWell(
                      onTap: _toggleMute,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          _currentVolume <= 0
                              ? Icons.volume_off
                              : _currentVolume < 50
                                  ? Icons.volume_down
                                  : Icons.volume_up,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  // 音量数字显示
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${_currentVolume.toInt()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 常驻音量进度条（宽度自适应，拖动时不自动隐藏控制台）
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 300)
                        .clamp(60.0, 200.0)
                        .toDouble(),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 9,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: _currentVolume.clamp(0.0, 100.0),
                        min: 0,
                        max: 100,
                        onChanged: (v) => _setVolume(v),
                        onChangeStart: (_) {
                          _isAdjustingVolume = true;
                          _cancelHideTimer();
                          _mouseIdleTimer?.cancel();
                        },
                        onChangeEnd: (_) {
                          _isAdjustingVolume = false;
                          _startHideTimer();
                        },
                        activeColor: colors.iconActive,
                        inactiveColor: Colors.white30,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

// =============================================================================
// 带 Tooltip 的图标按钮（明显的悬浮提示）
// =============================================================================

/// 带明显悬浮提示的图标按钮
class _IconButtonWithTooltip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  const _IconButtonWithTooltip({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 2),
      preferBelow: false,
      verticalOffset: 20,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: iconSize),
        onPressed: onPressed,
      ),
    );
  }
}

/// 带明显悬浮提示的自定义组件按钮
class _TooltipButton extends StatelessWidget {
  final String tooltip;
  final Widget child;

  const _TooltipButton({required this.tooltip, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 2),
      preferBelow: false,
      verticalOffset: 20,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      child: child,
    );
  }
}
