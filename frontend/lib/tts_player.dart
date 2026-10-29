import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 课堂后端语音提醒（TTS 音频）的播放器。
///
/// 接口保持很小且可注入，方便测试用伪实现替换，避免触碰真实的音频
/// 硬件与平台通道。
abstract class TtsPlayer {
  /// 从头开始播放 [audio]；如果还有片段在播放/排队，则按顺序追加到队尾。
  ///
  /// 返回的 Future 在该片段播放完毕时完成；如果播放器在片段结束前被释放，
  /// 该 Future 可能永远不会完成，调用方不能依赖它一定会有结果。
  Future<void> play(Uint8List audio, {String? contentType});

  /// 释放底层播放器资源。
  Future<void> dispose();
}

/// 跨平台的 [TtsPlayer]，基于 audioplayers。
///
/// audioplayers 在所有受支持的平台上都能直接播放原始音频字节：Web 上
/// 转换为 data URI，Android/Windows 上使用内存字节，iOS/macOS/Linux 上
/// 写入临时文件。
///
/// 片段按先进先出顺序播放：多条呼叫同时到达时，语音提醒依次念完，
/// 而不是互相打断。
class AudioTtsPlayer implements TtsPlayer {
  AudioTtsPlayer() {
    _completeSubscription =
        _audioPlayer.onPlayerComplete.listen((_) => unawaited(_onClipEnded()));
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<_Clip> _queue = [];
  _Clip? _current;
  StreamSubscription<void>? _completeSubscription;
  bool _disposed = false;

  @override
  Future<void> play(Uint8List audio, {String? contentType}) {
    if (_disposed) {
      throw StateError('AudioTtsPlayer has been disposed.');
    }
    final clip = _Clip(audio, contentType);
    _queue.add(clip);
    unawaited(_advance());
    return clip.done.future;
  }

  /// 当前没有片段在播时，取出队首片段开始播放。
  Future<void> _advance() async {
    if (_disposed || _current != null || _queue.isEmpty) return;
    final clip = _queue.removeAt(0);
    _current = clip;
    try {
      // 传真实的 contentType（后端是 audio/wav），Web 端据此生成 data URI。
      await _audioPlayer.play(
        BytesSource(clip.audio, mimeType: clip.contentType ?? 'audio/wav'),
      );
    } catch (_) {
      // 启动失败：记下错误、继续队里的下一个片段。
      _current = null;
      if (!clip.done.isCompleted) {
        clip.done.completeError(
          StateError('音频播放失败：${clip.audio.length} 字节片段无法启动。'),
        );
      }
      unawaited(_advance());
    }
  }

  Future<void> _onClipEnded() async {
    final finished = _current;
    _current = null;
    if (finished != null && !finished.done.isCompleted) {
      finished.done.complete();
    }
    await _advance();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _completeSubscription?.cancel();
    await _audioPlayer.dispose();
  }
}

/// 排队中的一个语音片段。
class _Clip {
  _Clip(this.audio, this.contentType);

  final Uint8List audio;
  final String? contentType;
  final Completer<void> done = Completer<void>();
}
