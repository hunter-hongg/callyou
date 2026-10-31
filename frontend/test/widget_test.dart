import 'dart:convert';
import 'dart:typed_data';

import 'package:callyou/api_client.dart';
import 'package:callyou/device_wording.dart';
import 'package:callyou/main.dart';
import 'package:callyou/models.dart';
import 'package:callyou/screens/student_dashboard.dart';
import 'package:callyou/theme.dart';
import 'package:callyou/tts_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows the shared classroom login', (tester) async {
    await _useDesktopSize(tester);
    final fake = FakeClassroom();
    final api = ApiClient(
      httpClient: fake.client,
      baseUrl: 'http://classroom.test',
    );

    await tester.pumpWidget(CallYouApp(api: api));

    expect(find.text('登录课堂'), findsOneWidget);
    expect(find.text('课堂账号'), findsOneWidget);
    expect(find.text('课堂密码'), findsOneWidget);
    expect(find.text('进入课堂'), findsOneWidget);
    expect(find.textContaining('callyou / 123456'), findsOneWidget);
  });

  testWidgets('teacher can select a student and send a call', (tester) async {
    await _useDesktopSize(tester);
    final fake = FakeClassroom();
    final api = ApiClient(
      httpClient: fake.client,
      baseUrl: 'http://classroom.test',
    );

    await tester.pumpWidget(CallYouApp(api: api));
    await tester.tap(find.text('进入课堂'));
    await _pumpNetwork(tester);
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text(roleSelectionTitle), findsOneWidget);

    await tester.tap(find.text('教师端'));
    await tester.pump();
    expect(find.text('进入教师端'), findsOneWidget);

    await tester.tap(find.text('进入教师端'));
    await _pumpNetwork(tester);
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('课堂指挥台'), findsOneWidget);
    expect(find.text('张小明'), findsOneWidget);

    await tester.tap(find.text('张小明'));
    await tester.pump();
    await tester.ensureVisible(find.text('呼叫 张小明'));
    await tester.pump();
    await tester.tap(find.text('呼叫 张小明'));
    await _pumpNetwork(tester);

    expect(fake.createdCalls, 1);
    expect(find.text('等待学生确认'), findsOneWidget);
    expect(find.text('已向 张小明 发起呼叫'), findsOneWidget);

    fake.acknowledgeLatestInBackend();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('已确认'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unified student client receives all account calls',
    (tester,
    ) async {
      await _useDesktopSize(tester);
      final fake = FakeClassroom(seedPendingCalls: true);
      final ttsPlayer = FakeTtsPlayer();
      final api = ApiClient(
        httpClient: fake.client,
        baseUrl: 'http://classroom.test',
      );
      const session = AuthSession(
        account: 'callyou',
        displayName: 'CallYou 课堂',
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCallYouTheme(),
          home: StudentDashboard(api: api, session: session, ttsPlayer: ttsPlayer),
        ),
      );
      await _pumpNetwork(tester);
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('老师有 2 条呼叫待回应'), findsOneWidget);
      expect(fake.ttsRequests, hasLength(2));
      expect(
        fake.ttsRequests.any((text) => text.contains('张小明同学')),
        isTrue,
      );
      expect(
        fake.ttsRequests.any((text) => text.contains('李思思同学')),
        isTrue,
      );
      expect(ttsPlayer.rotations, isNotEmpty);
      expect(_rotationIds(ttsPlayer), containsAll(['call-1', 'call-2']));
      expect(
        find.textContaining('语音提醒正在循环播放'),
        findsOneWidget,
      );

      final pollsBefore = fake.pendingPollCount;
      final ttsRequestsBefore = fake.ttsRequests.length;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 120));

      expect(fake.pendingPollCount, greaterThan(pollsBefore));
      expect(fake.ttsRequests.length, ttsRequestsBefore);
      expect(find.text('老师有 2 条呼叫待回应'), findsOneWidget);

      await tester.tap(find.text('收到了，马上回应').first);
      await _pumpNetwork(tester);
      await tester.pump(const Duration(milliseconds: 320));

      expect(fake.acknowledgeCount, 1);
      expect(find.text('老师正在呼叫你'), findsOneWidget);
      // 被确认的那条立刻退出轮播，剩下那条继续循环。
      expect(_rotationIds(ttsPlayer), hasLength(1));

      await tester.tap(find.text('收到了，马上回应').first);
      await _pumpNetwork(tester);
      await tester.pump(const Duration(milliseconds: 320));

      expect(fake.acknowledgeCount, 2);
      expect(find.text('老师有 2 条呼叫待回应'), findsNothing);
      expect(find.text('老师正在呼叫你'), findsNothing);
      expect(find.text('2 条'), findsOneWidget);
      expect(fake.ttsRequests.length, ttsRequestsBefore);
      // 全部确认后轮播列表清空，声音停止。
      expect(ttsPlayer.rotations.last, isEmpty);

      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> _useDesktopSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _pumpNetwork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

/// 伪播放器最后一次收到的轮播 ID 列表。
List<String> _rotationIds(FakeTtsPlayer player) =>
    player.rotations.last.map((item) => item.id).toList();

class FakeClassroom {
  FakeClassroom({bool seedPendingCalls = false}) {
    if (seedPendingCalls) {
      _appendCall(
        studentId: 'student-1',
        message: '请到办公室来一下。',
        id: 'call-1',
        createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 20)),
      );
      _appendCall(
        studentId: 'student-2',
        message: '请回答这个问题。',
        id: 'call-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
      );
    }
  }

  late final MockClient client = MockClient(_handle);

  final List<Map<String, dynamic>> roster = [
    {'id': 'student-1', 'name': '张小明'},
    {'id': 'student-2', 'name': '李思思'},
    {'id': 'student-3', 'name': '王一诺'},
    {'id': 'student-4', 'name': '陈子涵'},
    {'id': 'student-5', 'name': '刘星辰'},
    {'id': 'student-6', 'name': '赵雨桐'},
  ];

  final List<Map<String, dynamic>> calls = [];
  final List<String> ttsRequests = [];
  bool studentOnline = false;
  int createdCalls = 0;
  int pendingPollCount = 0;
  int acknowledgeCount = 0;
  int _nextCallNumber = 1;
  String? lastCreatedCallId;

  Future<http.Response> _handle(http.Request request) async {
    final method = request.method;
    final segments = request.url.pathSegments;
    final path = request.url.path;

    if (method == 'POST' && path == '/api/auth/login') {
      final body = _decodeBody(request.body);
      if (body['account'] == 'callyou' && body['password'] == '123456') {
        return _json({'account': 'callyou', 'displayName': 'CallYou 课堂'});
      }
      return _json({'error': '课堂账号或密码不正确'}, status: 401);
    }

    if (method == 'GET' && path == '/api/students') {
      return _json({'students': roster, 'studentOnline': studentOnline});
    }

    if (method == 'GET' && path == '/api/calls/pending') {
      pendingPollCount++;
      studentOnline = true;
      final pending = calls.reversed
          .where((call) => call['acknowledgedAt'] == null)
          .toList();
      return _json({'calls': pending});
    }

    if (method == 'POST' && path == '/api/calls') {
      final body = _decodeBody(request.body);
      final studentId = body['studentId'] as String? ?? '';
      final student = roster.firstWhere(
        (item) => item['id'] == studentId,
        orElse: () => {'name': '学生'},
      );
      final call = _appendCall(
        studentId: studentId,
        message: (body['message'] as String? ?? '').trim().isEmpty
            ? '老师正在呼叫你，请尽快回应。'
            : (body['message'] as String).trim(),
        id: 'call-${_nextCallNumber++}',
        createdAt: DateTime.now().toUtc(),
        studentName: student['name'] as String,
      );
      createdCalls++;
      lastCreatedCallId = call['id'] as String;
      return _json({'call': call}, status: 201);
    }

    if (method == 'GET' && path == '/api/calls') {
      final studentId = request.url.queryParameters['studentId'];
      final result = calls.reversed
          .where((call) => studentId == null || call['studentId'] == studentId)
          .toList();
      return _json({'calls': result});
    }

    if (method == 'POST' &&
        segments.length == 4 &&
        segments[1] == 'calls' &&
        segments[3] == 'acknowledge') {
      acknowledgeCount++;
      final callId = segments[2];
      for (final call in calls) {
        if (call['id'] == callId) {
          call['status'] = 'acknowledged';
          call['acknowledgedAt'] = DateTime.now().toUtc().toIso8601String();
          return _json({'call': call});
        }
      }
      return _json({'error': '未找到该呼叫'}, status: 404);
    }

    if (method == 'POST' && path == '/api/tts') {
      final body = _decodeBody(request.body);
      ttsRequests.add(body['text'] as String? ?? '');
      return http.Response.bytes(
        // A minimal fake WAV recording; the real backend returns the audio
        // synthesized by MiMo.
        Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x04, 0x00, 0x00, 0x00]),
        200,
        headers: const {'content-type': 'audio/wav'},
      );
    }

    return _json({'error': 'not found'}, status: 404);
  }

  void acknowledgeLatestInBackend() {
    final id = lastCreatedCallId;
    for (final call in calls) {
      if (id == null || call['id'] == id) {
        call['status'] = 'acknowledged';
        call['acknowledgedAt'] = DateTime.now().toUtc().toIso8601String();
      }
    }
  }

  Map<String, dynamic> _appendCall({
    required String studentId,
    required String message,
    required String id,
    required DateTime createdAt,
    String? studentName,
  }) {
    final resolvedName =
        studentName ??
        roster.firstWhere(
              (item) => item['id'] == studentId,
              orElse: () => {'name': '学生'},
            )['name']
            as String;
    final call = <String, dynamic>{
      'id': id,
      'studentId': studentId,
      'studentName': resolvedName,
      'message': message,
      'status': 'ringing',
      'createdAt': createdAt.toIso8601String(),
    };
    calls.add(call);
    return call;
  }

  Map<String, dynamic> _decodeBody(String rawBody) {
    if (rawBody.trim().isEmpty) return {};
    final decoded = jsonDecode(rawBody);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  http.Response _json(Object payload, {int status = 200}) {
    return http.Response.bytes(
      utf8.encode(jsonEncode(payload)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// 记录轮播内容的伪播放器，不触碰真实音频硬件与平台通道。
class FakeTtsPlayer implements TtsPlayer {
  /// 每次 [setRotation] 收到的内容快照，最后一次即当前正在循环的列表。
  final List<List<Announcement>> rotations = [];

  @override
  Future<void> setRotation(List<Announcement> items) async {
    rotations.add(List.of(items));
  }

  @override
  Future<void> dispose() async {}
}
