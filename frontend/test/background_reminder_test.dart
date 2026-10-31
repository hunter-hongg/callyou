import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:callyou/android_tts_player.dart';
import 'package:callyou/tts_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Announcement _announcement(String id, int marker) => Announcement(
  id: id,
  audio: Uint8List.fromList([marker]),
  contentType: 'audio/wav',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioplayersPlatform platform;
  late List<List<String>> nativeLoops;
  late Directory cache;

  setUp(() {
    // AndroidTtsPlayer 的前台一半仍然走 audioplayers，假装成不需要落盘的
    // Windows 平台，让它直接走字节通道。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    AudioPlayer.preparationTimeout = const Duration(milliseconds: 10);
    platform = _FakeAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance =
        _FakeGlobalAudioplayersPlatform();

    cache = Directory.systemTemp.createTempSync('callyou-reminder');
    nativeLoops = [];

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('callyou/call_reminder'),
      (call) async {
        if (call.method == 'setLoop') {
          nativeLoops.add((call.arguments['files'] as List).cast<String>());
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache.path,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AudioPlayer.preparationTimeout = const Duration(seconds: 30);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  test('前台照 audioplayers 播，退到后台才把同一批文件交给原生循环', () async {
    final player = AndroidTtsPlayer();
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await pumpEventQueue();
    expect(platform.sources, [Uint8List.fromList([1])]);
    expect(nativeLoops, isEmpty, reason: '界面可见时不该让原生侧一起响');

    await player.sendToBackground();
    await pumpEventQueue();
    expect(platform.stops, 1, reason: '交接时 Flutter 侧收声');
    expect(nativeLoops.last, hasLength(1));
    expect(File(nativeLoops.last.single).existsSync(), isTrue);

    await player.resumeInForeground();
    await pumpEventQueue();
    expect(nativeLoops.last, isEmpty, reason: '回前台时原生侧停掉循环');
    expect(platform.resumes, 2);
  });

  test('后台期间新来的呼叫会同步更新原生轮播', () async {
    final player = AndroidTtsPlayer();
    addTearDown(player.dispose);

    await player.setRotation([_announcement('call-1', 1)]);
    await player.sendToBackground();
    nativeLoops.clear();

    await player.setRotation([
      _announcement('call-1', 1),
      _announcement('call-2', 2),
    ]);
    await pumpEventQueue();
    expect(nativeLoops.last, hasLength(2));
    expect(platform.resumes, 1, reason: '后台时 Flutter 侧不再接手新片段');

    await player.setRotation([]);
    await pumpEventQueue();
    expect(nativeLoops.last, isEmpty, reason: '全部确认后原生也不再循环');
  });
}

/// 只实现轮播逻辑用到的那几个方法，其余接口成员留空。
class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final StreamController<AudioEvent> _events =
      StreamController<AudioEvent>.broadcast();
  final List<Uint8List> sources = [];
  int resumes = 0;
  int stops = 0;

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
