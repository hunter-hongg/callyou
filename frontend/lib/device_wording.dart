import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// 面向用户的措辞按设备形态分组。
///
/// 桌面/网页上把学生端和教师端统称「电脑」，手机上再说「这台电脑」就成了
/// 错话；Android 的提醒还多一条前台通知，文案要跟着变。
enum DeviceKind { desktop, mobile, browser }

DeviceKind get deviceKind {
  if (kIsWeb) return DeviceKind.browser;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.iOS:
      return DeviceKind.mobile;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return DeviceKind.desktop;
  }
}

bool get isMobileDevice => deviceKind == DeviceKind.mobile;

/// 教师和学生两端统称。
String get classroomDeviceNoun {
  return switch (deviceKind) {
    DeviceKind.desktop => '教师和学生电脑',
    DeviceKind.mobile => '教师和学生设备',
    DeviceKind.browser => '教师和学生端网页',
  };
}

String get classroomDeviceLoginHint =>
  '演示账号已预填：callyou / 123456。$classroomDeviceNoun请使用同一账号登录。';

/// 语音提醒卡片后半句：应用不在前台时还播不播。
String get backgroundPlaybackNote {
  return switch (deviceKind) {
    DeviceKind.desktop => '窗口最小化或收进系统托盘时同样播放。',
    DeviceKind.mobile =>
      '退到后台或熄屏时，前台通知会接着循环播报。',
    DeviceKind.browser => '标签页保持打开时会持续播放。',
  };
}

/// 身份选择页标题：中文里设备名词前后都不能插空格，拼接放在这里做，
/// 免得散在各处的 `$变量` 插值写出「选择 这台电脑 的身份」这种断句。
String get roleSelectionTitle => switch (deviceKind) {
  DeviceKind.desktop => '选择这台电脑的身份',
  DeviceKind.mobile => '选择这台设备的身份',
  DeviceKind.browser => '选择这个浏览器的身份',
};

String get roleSelectionIntro => switch (deviceKind) {
  DeviceKind.desktop =>
    '教师端发起呼叫，学生端统一接收账号下的所有呼叫。这台电脑只扮演其中一个角色。',
  DeviceKind.mobile =>
    '教师端发起呼叫，学生端统一接收账号下的所有呼叫。这台设备只扮演其中一个角色。',
  DeviceKind.browser =>
    '教师端发起呼叫，学生端统一接收账号下的所有呼叫。这个浏览器只扮演其中一个角色。',
};

String get teacherRoleDescription => switch (deviceKind) {
  DeviceKind.desktop => '讲台电脑：从座次表点一位学生，写下说明并呼叫。',
  DeviceKind.mobile => '教师手机 / 平板：从座次表点一位学生，写下说明并呼叫。',
  DeviceKind.browser => '教师端网页：从座次表点一位学生，写下说明并呼叫。',
};

String get studentRoleDescription => switch (deviceKind) {
  DeviceKind.desktop => '学生电脑或班级大屏：接收本账号的全部呼叫。',
  DeviceKind.mobile => '学生手机、平板或班级大屏：接收本账号的全部呼叫。',
  DeviceKind.browser => '学生端网页或班级大屏：接收本账号的全部呼叫。',
};

String get teacherFooterLabel => switch (deviceKind) {
  DeviceKind.desktop => '讲台电脑',
  DeviceKind.mobile => '教师手机 / 平板',
  DeviceKind.browser => '教师端网页',
};

String get studentFooterLabel => switch (deviceKind) {
  DeviceKind.desktop => '学生电脑 / 班级大屏',
  DeviceKind.mobile => '学生手机 / 平板 / 大屏',
  DeviceKind.browser => '学生端网页 / 班级大屏',
};
