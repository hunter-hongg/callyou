import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:callyou/tts_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int marker) => Uint8List.fromList([marker]);

Announcement _announcement(String id, int marker) =>
    Announcement(id: id, audio: _bytes(marker), contentType: 'audio/wav');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioplayersPlatform platform;

  setUp(() {
    // audioplayers 在 Linux/macOS 上会先把字节写成临时文件（要走 path_provider），
    // 假装 Windows 让它直接走字节通道。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // 起播失败时不会等到默认的 30 秒就绪超时。
    AudioPlayer.preparationTimeout = const Duration(milliseconds: 10);
    platform = _FakeAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance =
        _FakeGlobalAudioplayersPlatform();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AudioPlayer.preparationTimeout = const Duration(seconds: 30);
  });

  test('一条语音念完后自动从头再来', () async {
    final player = AudioTtsPlayer();
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await pumpEventQueue();
    expect(platform.sources, [_bytes(1)]);
    expect(platform.resumes, 1);

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.resumes, 2, reason: '念完一轮后自动接着念下一轮');

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.resumes, 3);
  });

  test('换轮播内容不打断正在播的那段，从它后面那条接着念', () async {
    final player = AudioTtsPlayer();
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await pumpEventQueue();

    await player.setRotation([
      _announcement('call-1', 1),
      _announcement('call-2', 2),
    ]);
    await pumpEventQueue();
    expect(platform.resumes, 1, reason: 'call-1 还在播，不该被新内容打断');
    expect(platform.stops, 0);

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.sources, [_bytes(1), _bytes(2)]);
    expect(platform.resumes, 2);

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.sources.last, _bytes(1), reason: '第二轮回到第一条');
  });

  test('正在播的那条被确认时立刻停下，换剩下的那条', () async {
    final player = AudioTtsPlayer();
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await pumpEventQueue();

    await player.setRotation([_announcement('call-2', 2)]);
    await pumpEventQueue();
    expect(platform.stops, 1);
    expect(platform.sources, [_bytes(1), _bytes(2)]);

    // 全部确认：轮播列表清空，声音停止且不再有事件。
    await player.setRotation([]);
    await pumpEventQueue();
    expect(platform.stops, 2);
    expect(platform.resumes, 2);

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.resumes, 2, reason: '停止后不再起播');
  });

  test('起播失败时报给调用方并停止轮播', () async {
    platform.failOnSetSource = true;
    Object? reported;
    final player = AudioTtsPlayer(onPlayError: (error) => reported = error);
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await pumpEventQueue();
    expect(reported, isNotNull);

    platform.completeCurrent();
    await pumpEventQueue();
    expect(platform.resumes, 0, reason: '失败后不该继续重试');
  });
}

/// 只实现轮播逻辑用到的那几个方法，其余接口成员留空。
class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final StreamController<AudioEvent> _events =
      StreamController<AudioEvent>.broadcast();
  final List<Uint8List> sources = [];
  int resumes = 0;
  int stops = 0;
  bool failOnSetSource = false;

  void completeCurrent() =>
      _events.add(const AudioEvent(eventType: AudioEventType.complete));

  @override
  Future<void> create(String playerId) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) => _events.stream;

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    if (failOnSetSource) {
      throw StateError('没有可用的音频输出设备');
    }
    sources.add(bytes);
    _events.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> resume(String playerId) async {
    resumes++;
  }

  @override
  Future<void> stop(String playerId) async {
    stops++;
  }

  @override
  Future<void> dispose(String playerId) async {
    await _events.close();
  }

  @override
  Future<int?> getDuration(String playerId) async => 1000;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext ctx) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode mode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class _FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  final StreamController<GlobalAudioEvent> _events =
      StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _events.stream;

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}
}
