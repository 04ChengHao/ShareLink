import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_metadata/media_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/global_providers.dart';

/// 媒体时长探测服务（单例）
///
/// 用于探测视频/音频文件的时长并持久缓存，供文件详情弹窗与预览共用。
/// - 本地文件：URI 为 `file://路径`
/// - 远程文件：URI 为 `http://设备IP:38381/file?path=...`（ConnectionServer 支持 Range 与流式）
///
/// 缓存键与下载缓存一致：`设备名|文件名|文件大小`，跨分类复用，
/// 避免同一文件在不同分类下重复探测。
/// 时长写入 [StorageKeys.mediaDurations]（SharedPreferences），探测一次后直接读取。
class MediaDurationService {
  MediaDurationService._();
  static final MediaDurationService instance = MediaDurationService._();

  SharedPreferences? _prefs;

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('MediaDurationService.init() 未调用');
    }
    return p;
  }

  /// 由 Provider 初始化注入 SharedPreferences
  void init(SharedPreferences prefs) => _prefs = prefs;

  /// 生成缓存键
  String _key(String deviceName, String fileName, int? size) {
    return '$deviceName|$fileName|$size';
  }

  /// 读取全部时长缓存（key -> 毫秒）
  Map<String, int> _readAll() {
    final raw = _p.getString(StorageKeys.mediaDurations);
    if (raw == null) return <String, int>{};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // 明确返回可变 Map：getDuration/cacheDuration 会对其写入后回存
      return <String, int>{
        for (final e in map.entries) e.key: (e.value as num).toInt(),
      };
    } catch (e) {
      debugPrint('[MediaDuration] 解析时长缓存失败: $e');
      return <String, int>{};
    }
  }

  void _writeAll(Map<String, int> map) {
    _p.setString(
      StorageKeys.mediaDurations,
      jsonEncode(map),
    );
  }

  /// 清空所有已探测的媒体时长缓存
  void clearAll() {
    try {
      _p.remove(StorageKeys.mediaDurations);
    } catch (_) {}
  }

  /// 移除指定文件（文件名+大小）的全部时长缓存
  ///
  /// 缓存键为 `设备名|文件名|大小`，本机文件的设备名可能随调用场景不同，
  /// 这里按 `|文件名|大小` 后缀匹配移除所有设备的记录。
  /// 文件被删除（磁盘上已扫描不到）时调用，避免时长缓存残留累积。
  void removeDurationsForFile(String fileName, int? size) {
    if (fileName.isEmpty) return;
    try {
      final suffix = '|$fileName|$size';
      final all = _readAll();
      final keys = all.keys.where((k) => k.endsWith(suffix)).toList();
      if (keys.isEmpty) return;
      for (final k in keys) {
        all.remove(k);
      }
      _writeAll(all);
    } catch (e) {
      debugPrint('[MediaDuration] 移除时长缓存失败: $e');
    }
  }

  /// 获取文件时长（毫秒）
  ///
  /// [uri] 文件的访问 URI（本地 file:// 或远程 http://…）。
  /// 先查缓存，未命中则探测并写缓存。
  Future<int?> getDuration({
    required String deviceName,
    required String fileName,
    int? size,
    required String uri,
  }) async {
    final key = _key(deviceName, fileName, size);

    if (fileName.isEmpty) return null;

    final cached = _readAll()[key];
    if (cached != null && cached > 0) {
      return cached;
    }

    final probed = await _probe(uri);
    if (probed != null && probed > 0) {
      final all = _readAll();
      all[key] = probed;
      _writeAll(all);
      return probed;
    }
    return null;
  }

  /// 仅读取时长缓存（不探测、不写回），用于"有时长就显示、不重新扫描"
  int? getCachedDuration({
    required String deviceName,
    required String fileName,
    int? size,
  }) {
    if (fileName.isEmpty) return null;
    final cached = _readAll()[_key(deviceName, fileName, size)];
    return (cached != null && cached > 0) ? cached : null;
  }

  /// 由预览/播放场景拿到确定时长后回写缓存，供详情与后续访问复用
  ///
  /// 与 [getDuration] 用同一缓存键（设备|文件名|大小），保证预览拿到的
  /// 时长能被详情弹窗与下一次打开复用。
  void cacheDuration({
    required String deviceName,
    required String fileName,
    int? size,
    required int durationMs,
  }) {
    if (durationMs <= 0) return;
    try {
      final key = _key(deviceName, fileName, size);
      final all = _readAll();
      all[key] = durationMs;
      _writeAll(all);
    } catch (e) {
      debugPrint('[MediaDuration] 写入时长缓存失败: $e');
    }
  }

  /// 探测时长
  ///
  /// 本地文件优先用原生元数据插件快速读取（毫秒级、无需解码），
  /// 原生读不到（不支持的封装或损坏）或远程 URL 时回退到 media_kit 播放器探测。
  Future<int?> _probe(String uri) async {
    final path = _localPathFromUri(uri);
    if (path != null) {
      final local = await _probeLocalMetadata(path);
      if (local != null) return local;
    }
    return _probeViaMediaKit(uri);
  }

  /// 从 `file://` URI 中解析本地路径，非本地返回 null
  String? _localPathFromUri(String uri) {
    if (!uri.startsWith('file://')) return null;
    final raw = uri.replaceFirst('file://', '');
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  /// 用原生元数据插件读取本地文件时长（毫秒）
  Future<int?> _probeLocalMetadata(String path) async {
    if (path.isEmpty || !MediaMetadata.isSupported(path)) return null;
    try {
      final md = await MediaMetadata.read(path);
      final d = md?.duration;
      if (d != null && d.inMilliseconds > 0) return d.inMilliseconds;
    } catch (e) {
      debugPrint('[MediaDuration] 原生读取时长失败: $e ($path)');
    }
    return null;
  }

  /// 回退：用 media_kit 播放器探测时长
  Future<int?> _probeViaMediaKit(String uri) async {
    final player = Player();
    final completer = Completer<int?>();

    final sub = player.stream.duration.listen((d) {
      if (!completer.isCompleted && d != Duration.zero) {
        completer.complete(d.inMilliseconds);
      }
    });

    try {
      // open 也加超时，避免个别文件在播放器初始化时卡住导致整个调用挂起
      await player
          .open(Media(uri), play: false)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      final result = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          final d = player.state.duration;
          return d.inMilliseconds > 0 ? d.inMilliseconds : null;
        },
      );
      return result;
    } catch (e) {
      debugPrint('[MediaDuration] 探测时长失败: $e ($uri)');
      return null;
    } finally {
      sub.cancel();
      player.dispose();
    }
  }
}