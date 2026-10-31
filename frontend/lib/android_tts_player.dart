import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'call_reminder.dart';
import 'tts_player.dart';

/// Android 版的 [TtsPlayer]：语音落到缓存目录，退到后台时交给前台服务播。
///
/// 前台时仍旧用 audioplayers 播（跟其他平台一条路径，调试期也听得见）；
/// [sendToBackground] 之后停掉自己的播放器，换成原生 MediaPlayer 循环同一批
/// 文件，回前台时反向交接。任何时刻只有一边在响。
class AndroidTtsPlayer implements TtsPlayer {
  AndroidTtsPlayer({this.onPlayError});

  /// 某一段语音准备失败时回调（落盘失败、文件不在），语义同 [AudioTtsPlayer.onPlayError]。
  final void Function(Object error)? onPlayError;

  Directory? _directory;
  final Map<String, String> _files = {};
  List<Announcement> _rotation = const [];
  List<String> _order = const [];
  AudioTtsPlayer? _foregroundPlayer;
  bool _backgrounded = false;

  @override
  Future<void> setRotation(List<Announcement> items) async {
    _rotation = List.of(items);
    _files.removeWhere((id, _) => !items.any((item) => item.id == id));
    _order = await _pathsFor(items);

    if (_backgrounded) {
      // 轮播内容变了（新呼叫进来或旧的被确认），原生侧要跟着换列表。
      await CallReminder.setLoop(_order);
      return;
    }
    if (items.isEmpty) {
      await _foregroundPlayer?.setRotation(const []);
      return;
    }
    final player = _foregroundPlayer ??= AudioTtsPlayer(
      onPlayError: _reportPlayError,
    );
    await player.setRotation(
      items.where((item) => _files.containsKey(item.id)).toList(),
    );
  }

  /// 退到后台：Flutter 收声，同一批文件交给前台服务继续循环。
  Future<void> sendToBackground() async {
    if (_backgrounded) return;
    _backgrounded = true;
    await _foregroundPlayer?.setRotation(const []);
    await CallReminder.setLoop(_order);
  }

  /// 回到前台：停掉原生循环，Flutter 重新按轮播顺序起播。
  Future<void> resumeInForeground() async {
    if (!_backgrounded) return;
    _backgrounded = false;
    await CallReminder.setLoop(const []);
    await setRotation(_rotation);
  }

  Future<List<String>> _pathsFor(List<Announcement> items) async {
    final paths = <String>[];
    for (final item in items) {
      final path = _files[item.id] ?? await _write(item);
      if (path != null) paths.add(path);
    }
    if (paths.length != items.length) {
      onPlayError?.call(StateError('语音提醒写入缓存失败'));
    }
    return paths;
  }

  void _reportPlayError(Object error) {
    _rotation = const [];
    onPlayError?.call(error);
  }

  Future<String?> _write(Announcement item) async {
    try {
      final directory = _directory ??= await getApplicationCacheDirectory();
      final extension = switch (item.contentType) {
        'audio/mpeg' => 'mp3',
        'audio/ogg' => 'ogg',
        'audio/aac' => 'aac',
        _ => 'wav',
      };
      final file = File(
        '${directory.path}/call_${item.id}_${item.audio.length}.$extension',
      );
      if (!file.existsSync() || file.lengthSync() != item.audio.length) {
        await file.writeAsBytes(item.audio.toList(), flush: true);
      }
      _files[item.id] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _rotation = const [];
    _order = const [];
    _files.clear();
    _backgrounded = false;
    await _foregroundPlayer?.dispose();
    _foregroundPlayer = null;
    await CallReminder.setLoop(const []);
  }
}

/// 供界面侧选择默认播放器。
///
/// Android 的 debug 构建仍旧只用 audioplayers：真机调试时前台就能听到声音，
/// 也不用跟通知权限和后台限制较劲。
TtsPlayer createDefaultTtsPlayer({void Function(Object error)? onPlayError}) {
  if (CallReminder.isSupported && !kDebugMode) {
    return AndroidTtsPlayer(onPlayError: onPlayError);
  }
  return AudioTtsPlayer(onPlayError: onPlayError);
}
