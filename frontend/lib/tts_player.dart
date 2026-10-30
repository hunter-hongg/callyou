import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 一段需要反复播报的语音，通常对应一条还没被确认的呼叫。
class Announcement {
  const Announcement({
    required this.id,
    required this.audio,
    this.contentType,
  });

  /// 调用方用来标识这段语音的键（这里是呼叫 ID）；换内容即换 id 或替换同 id。
  final String id;

  final Uint8List audio;
  final String? contentType;
}

/// 课堂后端语音提醒（TTS 音频）的播放器。
///
/// 接口保持很小且可注入，方便测试用伪实现替换，避免触碰真实的音频
/// 硬件与平台通道。
abstract class TtsPlayer {
  /// 让 [items] 成为当前要循环播报的全部内容：按列表顺序念完一轮，再从
  /// 头开始，直到下一次调用本方法替换列表；传空列表即停止。
  ///
  /// 重复调用不会打断正在播的那一段——新的轮播从它结束后接上；如果正在
  /// 播的那一段已经不在新列表里（例如那条呼叫刚被确认），则立刻停下。
  ///
  /// 窗口失焦、最小化或收进系统托盘都不影响这里的播放。
  Future<void> setRotation(List<Announcement> items);

  /// 释放底层播放器资源。
  Future<void> dispose();
}

/// 跨平台的 [TtsPlayer]，基于 audioplayers。
///
/// audioplayers 在所有受支持的平台上都能直接播放原始音频字节：Web 上
/// 转换为 data URI，Android/Windows 上使用内存字节，iOS/macOS/Linux 上
/// 写入临时文件。
class AudioTtsPlayer implements TtsPlayer {
  AudioTtsPlayer({this.onPlayError}) {
    _completeSubscription =
        _audioPlayer.onPlayerComplete.listen((_) => unawaited(_onClipEnded()));
  }

  /// 某一段语音起播失败时回调（例如这台机器没有可用的音频输出）。
  /// 报错后轮播会停下来，由调用方决定要不要重试。
  final void Function(Object error)? onPlayError;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Announcement> _rotation = const [];
  int _cursor = 0;
  Announcement? _current;
  StreamSubscription<void>? _completeSubscription;
  bool _disposed = false;

  @override
  Future<void> setRotation(List<Announcement> items) async {
    if (_disposed) return;
    _rotation = List.of(items);
    if (_rotation.isEmpty) {
      await _stopCurrent();
      return;
    }
    final playing = _current;
    if (playing == null) {
      _cursor = 0;
      await _pump();
      return;
    }
    final index = _rotation.indexWhere((item) => item.id == playing.id);
    if (index < 0) {
      // 正在播的那段已经不该再播了：停掉它，从新列表第一条开始。
      await _stopCurrent();
      _cursor = 0;
      await _pump();
      return;
    }
    // 把游标对准正在播的这段，它结束后自然接着念下一段。
    _cursor = index;
  }

  /// 当前没有片段在播时，按轮播顺序起下一段。
  Future<void> _pump() async {
    if (_disposed || _current != null || _rotation.isEmpty) return;
    final item = _rotation[_cursor % _rotation.length];
    _current = item;
    try {
      // 传真实的 contentType（后端是 audio/wav），Web 端据此生成 data URI。
      await _audioPlayer.play(
        BytesSource(item.audio, mimeType: item.contentType ?? 'audio/wav'),
      );
    } catch (error) {
      // 起播失败：同一段重试只会同样失败，直接停掉轮播并通知调用方。
      _current = null;
      _rotation = const [];
      onPlayError?.call(error);
    }
  }

  Future<void> _onClipEnded() async {
    // _current 为空说明这是停止/替换之后才姗姗来迟的完成事件，忽略。
    if (_disposed || _current == null) return;
    _current = null;
    if (_rotation.isEmpty) return;
    _cursor = (_cursor + 1) % _rotation.length;
    await _pump();
  }

  Future<void> _stopCurrent() async {
    if (_current == null) return;
    _current = null;
    await _audioPlayer.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _rotation = const [];
    _current = null;
    await _completeSubscription?.cancel();
    await _audioPlayer.dispose();
  }
}
