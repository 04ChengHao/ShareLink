import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

/// 音频播放器组件（基于 media_kit，全平台支持）
///
/// 替代 just_audio，解决 Windows 端无原生实现的 MissingPluginException。
/// 提供：
/// - 播放/暂停
/// - 进度拖动
/// - 快进/快退 10s
class AudioViewer extends StatefulWidget {
  final String mediaUri;
  final String title;

  /// 当播放器确定媒体真实时长时回调（用于把时长回写入缓存）
  final void Function(Duration duration)? onDurationKnown;

  const AudioViewer({
    super.key,
    required this.mediaUri,
    required this.title,
    this.onDurationKnown,
  });

  @override
  State<AudioViewer> createState() => _AudioViewerState();
}

class _AudioViewerState extends State<AudioViewer> {
  late final Player _player;
  bool _initialized = false;
  bool _failed = false;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.open(Media(widget.mediaUri));

      _subscriptions.add(_player.stream.playing.listen((_) {
        if (mounted) setState(() {});
      }));
      _subscriptions.add(_player.stream.position.listen((_) {
        if (mounted) setState(() {});
      }));
      _subscriptions.add(_player.stream.duration.listen((d) {
        if (mounted) setState(() {});
        if (d > Duration.zero) widget.onDurationKnown?.call(d);
      }));
      _subscriptions.add(_player.stream.completed.listen((_) {
        if (mounted) setState(() {});
      }));
      _subscriptions.add(_player.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          setState(() => _failed = true);
        }
      }));

      if (mounted) {
        setState(() => _initialized = true);
        _player.play();
      }
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _seekRelative(int seconds) {
    final pos = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    final clamped = pos < Duration.zero
        ? Duration.zero
        : (pos > duration ? duration : pos);
    _player.seek(clamped);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

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
          ],
        ),
      );
    }

    if (!_initialized) {
      return Center(
        child: CircularProgressIndicator(color: colors.iconActive),
      );
    }

    final position = _player.state.position;
    final duration = _player.state.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final isPlaying = _player.state.playing;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 音频封面图标
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.primaryWithAlpha(0.3),
                    colors.primaryWithAlpha(0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.audio_file,
                size: 80,
                color: colors.iconActive,
              ),
            ),
            const SizedBox(height: 24),
            // 文件名
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            // 进度条
            Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                Expanded(
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (v) {
                      _player.seek(
                        Duration(
                          milliseconds:
                              (v * duration.inMilliseconds).toInt(),
                        ),
                      );
                    },
                    activeColor: colors.iconActive,
                    inactiveColor: colors.inputBg,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(Icons.replay_10, color: colors.textSecondary),
                  onPressed: () => _seekRelative(-10),
                ),
                const SizedBox(width: 24),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.iconActive,
                  ),
                  child: IconButton(
                    iconSize: 36,
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 40,
                  icon: Icon(Icons.forward_10, color: colors.textSecondary),
                  onPressed: () => _seekRelative(10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
