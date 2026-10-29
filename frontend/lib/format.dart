String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String formatClockWithSeconds(DateTime time) {
  final local = time.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}

String formatSessionDate(DateTime time) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final local = time.toLocal();
  return '${local.month}月${local.day}日 · ${weekdays[local.weekday - 1]}';
}
