import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('callyou/call_reminder');

/// Android 前台服务「callyou/call_reminder」的 Dart 门面。
///
/// 每个调用都自行容错：平台上没有这个通道时返回 false，不抛。
///
/// 服务本身只认绝对路径的音频文件，也不知道呼叫是什么内容；轮询、合成、
/// 文案都留在 Dart 这边，跨界的只有「起来 / 播这几段 / 通知写这行字 / 停」。
class CallReminder {
  const CallReminder._();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
      return true;
    } on MissingPluginException {
      // 其他平台、以及测试里没有这个通道：静默按「不可用」处理。
      return false;
    } catch (_) {
      // 前台服务起不来（权限被拒、系统限制）不该让课堂界面崩掉。
      return false;
    }
  }

  /// 拉起常驻通知。返回 false 表示这台机器上没有可用的前台服务。
  static Future<bool> start() => _invoke('start');

  static Future<bool> stop() => _invoke('stop');

  /// 交给原生侧循环播放的内容；列表不变时重复调用不会打断正在播的那一段。
  static Future<bool> setLoop(List<String> files) => _invoke('setLoop', {'files': files});

  static Future<bool> setStatus(String text) => _invoke('setStatus', {'text': text});
}
