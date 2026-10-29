import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      baseUrl = (baseUrl ?? BackendConfig.baseUrl).replaceFirst(
        RegExp(r'/+$'),
        '',
      );

  static const _timeout = Duration(seconds: 8);
  // MiMo TTS synthesis takes far longer than the other API calls; keep it a
  // bit looser than the backend's 30-second upstream limit so the backend
  // reports the real error instead of the client giving up first.
  static const _ttsTimeout = Duration(seconds: 35);
  static const _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
  };

  final http.Client _http;
  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  Future<http.Response> _send(
    Future<http.Response> request, {
    Duration? timeout,
    String? timeoutMessage,
  }) async {
    try {
      return await request.timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw ApiException(
        timeoutMessage ?? '连接课堂服务器超时，请检查后端是否已启动。',
      );
    } on http.ClientException {
      throw const ApiException('无法连接课堂服务器，请确认后端地址与网络。');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('网络请求失败，请稍后再试。');
    }
  }

  Future<AuthSession> login({
    required String account,
    required String password,
  }) async {
    final response = await _send(
      _http.post(
        _uri('/api/auth/login'),
        headers: _jsonHeaders,
        body: jsonEncode({'account': account, 'password': password}),
      ),
    );
    _ensureSuccess(response, '登录失败');
    return AuthSession.fromJson(_object(response, '登录响应格式不正确'));
  }

  Future<void> register({
    required String username,
    required String password,
    required String students,
  }) async {
    final response = await _send(
      _http.post(
        _uri('/api/auth/register'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'username': username,
          'password': password,
          'students': students,
        }),
      ),
    );
    _ensureSuccess(response, '注册失败');
  }

  Future<StudentRoster> fetchStudents() async {
    final response = await _send(
      _http.get(
        _uri('/api/students'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    _ensureSuccess(response, '获取学生名单失败');
    try {
      return StudentRoster.fromJson(_object(response, '学生名单格式不正确'));
    } catch (_) {
      throw const ApiException('学生名单格式不正确');
    }
  }

  Future<CallRecord> createCall({
    required String studentId,
    required String message,
  }) async {
    final response = await _send(
      _http.post(
        _uri('/api/calls'),
        headers: _jsonHeaders,
        body: jsonEncode({'studentId': studentId, 'message': message}),
      ),
    );
    _ensureSuccess(response, '发起呼叫失败');
    final payload = _object(response, '呼叫响应格式不正确');
    final rawCall = payload['call'];
    if (rawCall is! Map<String, dynamic>) {
      throw const ApiException('呼叫响应格式不正确');
    }
    return CallRecord.fromJson(rawCall);
  }

  Future<List<CallRecord>> fetchPendingCalls() async {
    final response = await _send(
      _http.get(
        _uri('/api/calls/pending'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    _ensureSuccess(response, '检查新呼叫失败');
    final payload = _object(response, '呼叫响应格式不正确');
    final rawCalls = payload['calls'];
    if (rawCalls is! List) {
      throw const ApiException('呼叫响应格式不正确');
    }
    try {
      return rawCalls
          .map((item) => CallRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      throw const ApiException('呼叫响应格式不正确');
    }
  }

  Future<CallRecord> acknowledgeCall({required String callId}) async {
    final response = await _send(
      _http.post(
        _uri('/api/calls/${Uri.encodeComponent(callId)}/acknowledge'),
        headers: _jsonHeaders,
      ),
    );
    _ensureSuccess(response, '确认呼叫失败');
    final payload = _object(response, '呼叫响应格式不正确');
    final rawCall = payload['call'];
    if (rawCall is! Map<String, dynamic>) {
      throw const ApiException('呼叫响应格式不正确');
    }
    return CallRecord.fromJson(rawCall);
  }

  Future<List<CallRecord>> fetchCalls({
    String? studentId,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (studentId != null) {
      query['studentId'] = studentId;
    }
    final response = await _send(
      _http.get(
        _uri('/api/calls', query),
        headers: const {'Accept': 'application/json'},
      ),
    );
    _ensureSuccess(response, '获取呼叫记录失败');
    final payload = _object(response, '呼叫记录格式不正确');
    final rawCalls = payload['calls'];
    if (rawCalls is! List) {
      throw const ApiException('呼叫记录格式不正确');
    }
    try {
      return rawCalls
          .map((item) => CallRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      throw const ApiException('呼叫记录格式不正确');
    }
  }

  Future<TtsResult> synthesize(String text) async {
    final response = await _send(
      _http.post(
        _uri('/api/tts'),
        headers: _jsonHeaders,
        body: jsonEncode({'text': text}),
      ),
      timeout: _ttsTimeout,
      timeoutMessage: '语音合成超时，请缩短文字后重试。',
    );
    _ensureSuccess(response, '获取语音提醒失败');
    return TtsResult(
      audio: response.bodyBytes,
      contentType: response.headers['content-type'],
    );
  }

  void _ensureSuccess(http.Response response, String fallback) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ApiException(
      _errorMessage(response) ?? '$fallback（HTTP ${response.statusCode}）',
      statusCode: response.statusCode,
    );
  }

  String? _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _object(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Falls through to the caller-friendly error below.
    }
    throw ApiException(fallback);
  }
}
