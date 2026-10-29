import 'dart:typed_data';

class AuthSession {
  const AuthSession({required this.account, required this.displayName});

  final String account;
  final String displayName;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      account: json['account'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'CallYou 课堂',
    );
  }
}

class Student {
  const Student({required this.id, required this.name});

  final String id;
  final String name;

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}

class StudentRoster {
  const StudentRoster({required this.students, required this.studentOnline});

  final List<Student> students;
  final bool studentOnline;

  factory StudentRoster.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['students'];
    if (rawStudents is! List) {
      throw const FormatException('学生名单格式不正确');
    }
    return StudentRoster(
      students: rawStudents
          .map((item) => Student.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      studentOnline: json['studentOnline'] as bool? ?? false,
    );
  }
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.message,
    required this.status,
    required this.createdAt,
    this.acknowledgedAt,
  });

  final String id;
  final String studentId;
  final String studentName;
  final String message;
  final String status;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;

  bool get isAcknowledged => acknowledgedAt != null || status == 'acknowledged';

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    final acknowledgedRaw = json['acknowledgedAt'] as String?;
    return CallRecord(
      id: json['id'] as String,
      studentId: json['studentId'] as String,
      studentName: json['studentName'] as String,
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'ringing',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      acknowledgedAt: acknowledgedRaw == null
          ? null
          : DateTime.tryParse(acknowledgedRaw),
    );
  }

  CallRecord acknowledgedCopy(DateTime time) {
    return CallRecord(
      id: id,
      studentId: studentId,
      studentName: studentName,
      message: message,
      status: 'acknowledged',
      createdAt: createdAt,
      acknowledgedAt: time,
    );
  }
}

class TtsResult {
  const TtsResult({
    required this.audio,
    required this.contentType,
  });

  final Uint8List audio;
  final String? contentType;

  bool get hasAudio => audio.isNotEmpty;
}
